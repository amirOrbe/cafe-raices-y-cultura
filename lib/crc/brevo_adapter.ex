defmodule CRC.BrevoAdapter do
  @moduledoc "Swoosh adapter for Brevo's transactional email REST API."

  use Swoosh.Adapter, required_config: [:api_key]

  @api_url "https://api.brevo.com/v3/smtp/email"

  @impl true
  def deliver(%Swoosh.Email{} = email, config) do
    api_key = Keyword.fetch!(config, :api_key)

    {from_name, from_email} = email.from

    to =
      Enum.map(email.to, fn
        {name, addr} when name != "" -> %{name: name, email: addr}
        {_, addr} -> %{email: addr}
      end)

    body =
      %{
        sender: %{name: from_name, email: from_email},
        to: to,
        subject: email.subject,
        htmlContent: email.html_body,
        textContent: email.text_body
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    case Req.post(@api_url,
           json: body,
           headers: [{"api-key", api_key}, {"accept", "application/json"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, %{}}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
