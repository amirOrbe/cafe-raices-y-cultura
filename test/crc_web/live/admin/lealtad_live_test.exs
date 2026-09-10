defmodule CRCWeb.Admin.LealtadLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  alias CRC.CRM

  defp admin_conn(conn) do
    admin = create_admin()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  describe "access" do
    test "redirects a non-admin", %{conn: conn} do
      empleado = create_waiter()
      conn = init_test_session(conn, %{"user_id" => empleado.id})
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/lealtad")
    end
  end

  describe "visit tiers" do
    setup %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      %{conn: conn}
    end

    test "creates a visit tier", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/admin/lealtad")
      lv |> element("#btn-new-tier") |> render_click()

      html =
        lv
        |> form("#tier-form",
          loyalty_reward: %{
            visits_required: "6",
            name: "Tarjeta",
            benefit: "Café gratis",
            repeatable: "true",
            active: "true"
          }
        )
        |> render_submit()

      assert html =~ "creado correctamente"
      assert html =~ "Tarjeta"

      assert [%{visits_required: 6, benefit: "Café gratis"}] =
               CRM.list_reward_tiers(kind: "visits")
    end

    test "shows a validation error when visits_required is missing", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/admin/lealtad")
      lv |> element("#btn-new-tier") |> render_click()

      html =
        lv
        |> form("#tier-form", loyalty_reward: %{visits_required: "", name: "X", benefit: "Y"})
        |> render_submit()

      assert html =~ "requerido para niveles por visitas"
    end

    test "edits and deactivates a tier", %{conn: conn} do
      tier = create_reward_tier(%{name: "Original", visits_required: 5})
      {:ok, lv, _} = live(conn, ~p"/admin/lealtad")

      lv |> element("#btn-edit-tier-d-#{tier.id}") |> render_click()

      lv
      |> form("#tier-form",
        loyalty_reward: %{
          visits_required: "5",
          name: "Renombrado",
          benefit: "Café",
          repeatable: "true",
          active: "true"
        }
      )
      |> render_submit()

      assert CRM.get_reward!(tier.id).name == "Renombrado"

      lv
      |> element("#btn-edit-tier-d-#{tier.id} ~ button[phx-click='toggle_tier']")
      |> render_click()

      refute CRM.get_reward!(tier.id).active
    end
  end

  describe "birthday config" do
    setup %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      %{conn: conn}
    end

    test "creates the birthday reward on first save", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/admin/lealtad")

      html =
        lv
        |> form("#birthday-form",
          loyalty_reward: %{
            active: "true",
            name: "Cumpleaños",
            benefit: "Postre gratis",
            birthday_window_days: "2"
          }
        )
        |> render_submit()

      assert html =~ "cumpleaños guardado"
      reward = CRM.get_birthday_reward()
      assert reward.benefit == "Postre gratis"
      assert reward.birthday_window_days == 2
    end

    test "updates the existing birthday reward", %{conn: conn} do
      create_birthday_reward(%{benefit: "Viejo"})
      {:ok, lv, _} = live(conn, ~p"/admin/lealtad")

      lv
      |> form("#birthday-form",
        loyalty_reward: %{
          active: "true",
          name: "Cumpleaños",
          benefit: "Nuevo",
          birthday_window_days: "0"
        }
      )
      |> render_submit()

      assert CRM.get_birthday_reward().benefit == "Nuevo"
    end
  end
end
