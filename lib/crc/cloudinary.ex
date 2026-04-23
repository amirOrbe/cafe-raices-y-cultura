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
  """

  @upload_base "https://api.cloudinary.com/v1_1"

  @doc """
  Uploads the file at `path` to Cloudinary and returns the secure HTTPS URL.

  Options:
    - `:folder` — destination folder in Cloudinary (default: "menu")

  Returns `{:ok, url}` or `{:error, reason}`.
  """
  @spec upload(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def upload(path, opts \\ []) do
    cfg = config()
    folder = Keyword.get(opts, :folder, "menu")
    timestamp = System.os_time(:second)

    signature = sign(timestamp, folder, cfg[:api_secret])

    url = "#{@upload_base}/#{cfg[:cloud_name]}/image/upload"

    body = [
      file: {:file, path},
      api_key: cfg[:api_key],
      timestamp: to_string(timestamp),
      folder: folder,
      signature: signature
    ]

    case Req.post(url, form_multipart: body) do
      {:ok, %{status: 200, body: %{"secure_url" => secure_url}}} ->
        {:ok, secure_url}

      {:ok, %{status: status, body: body}} ->
        {:error, "Cloudinary error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp config do
    Application.get_env(:crc, :cloudinary, [])
  end

  # Produces the SHA-1 signature Cloudinary requires for authenticated uploads.
  defp sign(timestamp, folder, api_secret) do
    payload = "folder=#{folder}&timestamp=#{timestamp}#{api_secret}"

    :crypto.hash(:sha, payload)
    |> Base.encode16(case: :lower)
  end
end
