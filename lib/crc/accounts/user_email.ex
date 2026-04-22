defmodule CRC.Accounts.UserEmail do
  @moduledoc """
  Builds transactional email messages for user account events.

  Emails are composed with Swoosh and delivered via the configured mailer
  adapter (Local in dev, Resend in production).

  ## Sender address
  In dev, emails are sent from `onboarding@resend.dev` (Resend's shared test
  domain). Before going to production, update `@from` to a verified domain
  address (e.g. `noreply@cafercyc.com`).
  """

  import Swoosh.Email

  # Update this address once your domain is verified in Resend.
  # Dev fallback: onboarding@resend.dev (Resend shared domain, no verification needed).
  @from {"Café Raíces y Cultura",
         Application.compile_env(:crc, :mailer_from_address, "onboarding@resend.dev")}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Builds a welcome email with an email-confirmation link for a newly created user.

  `user`             — the newly created `%User{}` struct.
  `confirmation_url` — the signed, time-limited URL for email confirmation.
  """
  @spec welcome_confirmation(map(), String.t()) :: Swoosh.Email.t()
  def welcome_confirmation(%{name: name, email: email} = _user, confirmation_url) do
    new()
    |> to({name, email})
    |> from(@from)
    |> subject("Bienvenido a Café Raíces y Cultura — confirma tu cuenta")
    |> html_body(build_html(name, confirmation_url))
    |> text_body(build_text(name, confirmation_url))
  end

  # ---------------------------------------------------------------------------
  # HTML template (inline styles required for email client compatibility)
  # ---------------------------------------------------------------------------

  defp build_html(name, url) do
    first_name = name |> String.split() |> List.first()
    year = Date.utc_today().year

    """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Bienvenido a Café Raíces y Cultura</title>
    </head>
    <body style="margin:0;padding:0;background-color:#f5f0e8;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">

      <table role="presentation" cellpadding="0" cellspacing="0" width="100%"
             style="background-color:#f5f0e8;padding:40px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" cellpadding="0" cellspacing="0"
                   width="100%" style="max-width:560px;">

              <!-- Header -->
              <tr>
                <td align="center" style="padding-bottom:24px;">
                  <h1 style="margin:0;font-size:22px;font-weight:700;color:#5c3d1e;
                              letter-spacing:-0.5px;">
                    Café Raíces y Cultura
                  </h1>
                  <p style="margin:4px 0 0;font-size:13px;color:#9c7a5a;">
                    Sistema de gestión interna
                  </p>
                </td>
              </tr>

              <!-- Card -->
              <tr>
                <td style="background-color:#ffffff;border-radius:16px;
                           padding:40px 36px;box-shadow:0 2px 8px rgba(0,0,0,0.06);">

                  <p style="margin:0 0 16px;font-size:20px;font-weight:700;color:#1a1a1a;">
                    ¡Bienvenido, #{first_name}!
                  </p>

                  <p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#444;">
                    Tu cuenta en el sistema de Café Raíces y Cultura ha sido creada.
                    Para activarla y confirmar tu correo electrónico, haz clic en el
                    botón de abajo.
                  </p>

                  <p style="margin:0 0 8px;font-size:13px;color:#888;">
                    Este enlace es válido por <strong>7 días</strong>.
                  </p>

                  <!-- CTA button -->
                  <table role="presentation" cellpadding="0" cellspacing="0"
                         style="margin:28px 0;">
                    <tr>
                      <td style="border-radius:10px;background-color:#6b4226;">
                        <a href="#{url}"
                           style="display:inline-block;padding:14px 32px;
                                  font-size:15px;font-weight:600;color:#ffffff;
                                  text-decoration:none;border-radius:10px;">
                          Confirmar mi cuenta
                        </a>
                      </td>
                    </tr>
                  </table>

                  <p style="margin:0 0 8px;font-size:13px;color:#888;">
                    Si el botón no funciona, copia y pega este enlace en tu navegador:
                  </p>
                  <p style="margin:0;font-size:12px;color:#9c7a5a;word-break:break-all;">
                    #{url}
                  </p>

                  <hr style="border:none;border-top:1px solid #f0e8dc;margin:28px 0;" />

                  <p style="margin:0;font-size:13px;color:#aaa;line-height:1.5;">
                    Si no esperabas este correo, puedes ignorarlo de forma segura.
                    Tu cuenta no se activará hasta que confirmes tu dirección.
                  </p>

                </td>
              </tr>

              <!-- Footer -->
              <tr>
                <td align="center" style="padding-top:24px;">
                  <p style="margin:0;font-size:12px;color:#b8a898;">
                    © #{year} Café Raíces y Cultura · Todos los derechos reservados
                  </p>
                </td>
              </tr>

            </table>
          </td>
        </tr>
      </table>

    </body>
    </html>
    """
  end

  # ---------------------------------------------------------------------------
  # Plain-text fallback
  # ---------------------------------------------------------------------------

  defp build_text(name, url) do
    first_name = name |> String.split() |> List.first()

    """
    ¡Bienvenido, #{first_name}!

    Tu cuenta en el sistema de Café Raíces y Cultura ha sido creada.
    Para activarla, confirma tu correo electrónico visitando el siguiente enlace:

    #{url}

    Este enlace es válido por 7 días.

    Si no esperabas este correo, puedes ignorarlo de forma segura.

    — Café Raíces y Cultura
    """
  end
end
