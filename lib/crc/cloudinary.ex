defmodule CRC.Cloudinary do
  @moduledoc """
  Thin client for uploading images to Cloudinary.

  Credentials are read from application config:

      config :crc, :cloudinary,
        cloud_name: "...",
        api_key: "...",
        api_secret: "..."

  The upload uses the authenticated REST API (server-side signed upload)
  so no unsigned presets are required.

  Multipart body is built manually so that no optional `:multipart` hex
  package is required — only Req (already a project dependency).
  """

  require Logger

  @upload_base "https://api.cloudinary.com/v1_1"

  @doc """
  Uploads the file at `path` to Cloudinary and returns the secure HTTPS URL.

  Options:
    - `:folder`       — destination folder in Cloudinary (default: "menu")
    - `:content_type` — MIME type of the file (default: "image/jpeg")

  Returns `{:ok, url}` or `{:error, reason}`.
  """
  @spec upload(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def upload(path, opts \\ []) do
    cfg = config()
    folder = Keyword.get(opts, :folder, "menu")
    content_type = Keyword.get(opts, :content_type, "image/jpeg")
    timestamp = System.os_time(:second)
    signature = sign(timestamp, folder, cfg[:api_secret])
    url = "#{@upload_base}/#{cfg[:cloud_name]}/image/upload"

    with {:ok, file_bytes} <- File.read(path) do
      boundary = "CRCBoundary#{:rand.uniform(999_999_999)}"
      filename = "upload#{ext_for(content_type)}"

      body =
        [
          multipart_text(boundary, "api_key", cfg[:api_key]),
          multipart_text(boundary, "timestamp", to_string(timestamp)),
          multipart_text(boundary, "folder", folder),
          multipart_text(boundary, "signature", signature),
          multipart_file(boundary, "file", file_bytes, content_type, filename),
          "--#{boundary}--\r\n"
        ]
        |> IO.iodata_to_binary()

      case Req.post(url,
             body: body,
             headers: [{"content-type", "multipart/form-data; boundary=#{boundary}"}]) do
        {:ok, %{status: 200, body: %{"secure_url" => secure_url}}} ->
          {:ok, secure_url}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Cloudinary HTTP #{status}: #{inspect(body)}")
          {:error, "Cloudinary error #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp config do
    Application.get_env(:crc, :cloudinary, [])
  end

  # Produces the SHA-1 signature Cloudinary requires for authenticated uploads.
  # Parameters must be in alphabetical order (folder < timestamp).
  defp sign(timestamp, folder, api_secret) do
    payload = "folder=#{folder}&timestamp=#{timestamp}#{api_secret}"

    :crypto.hash(:sha, payload)
    |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Manual multipart body builders — avoids the optional :multipart hex dep
  # ---------------------------------------------------------------------------

  defp multipart_text(boundary, name, value) do
    "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
  end

  defp multipart_file(boundary, name, content, content_type, filename) do
    [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\n",
      "Content-Type: #{content_type}\r\n\r\n",
      content,
      "\r\n"
    ]
  end

  defp ext_for("image/jpeg"), do: ".jpg"
  defp ext_for("image/png"), do: ".png"
  defp ext_for("image/webp"), do: ".webp"
  defp ext_for(_), do: ".jpg"
end
