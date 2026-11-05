defmodule CRCWeb.LoginThrottle do
  @moduledoc """
  Limits failed logins per IP and per email. The per-email limit stops guessing
  one account's password from many IPs.

  An attempt is counted before the password is checked, so simultaneous
  requests can't all be tried before the first failure is recorded. A
  successful login gives its attempt back.
  """

  alias CRC.RateLimiter

  @window :timer.minutes(15)
  @max_failures_per_ip 20
  @max_failures_per_email 10

  @message "Demasiados intentos. Espera unos minutos e intenta de nuevo."

  def message, do: @message

  @spec reserve(Plug.Conn.t(), String.t()) :: :ok | :error
  def reserve(conn, email) do
    ip_key = ip_key(conn)

    cond do
      RateLimiter.hit(ip_key, @max_failures_per_ip, @window) == :error ->
        :error

      RateLimiter.hit(email_key(email), @max_failures_per_email, @window) == :ok ->
        :ok

      true ->
        RateLimiter.release(ip_key, @window)
        :error
    end
  end

  @spec release(Plug.Conn.t(), String.t()) :: :ok
  def release(conn, email) do
    RateLimiter.release(ip_key(conn), @window)
    RateLimiter.release(email_key(email), @window)
  end

  defp ip_key(conn), do: {:login_ip, client_ip(conn)}
  defp email_key(email), do: {:login_email, email |> String.trim() |> String.downcase()}

  # Fly's proxy sets this header, overwriting any value the client sent. The
  # socket peer address would be the proxy itself.
  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
