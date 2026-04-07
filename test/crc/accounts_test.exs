defmodule CRC.AccountsTest do
  use CRC.DataCase, async: true

  alias CRC.Accounts
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp attrs_validos(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Ana López",
        email: "ana@cafe.com",
        role: "admin",
        password: "contraseña123"
      },
      overrides
    )
  end

  defp insertar_usuario(overrides \\ %{}) do
    attrs = attrs_validos(overrides)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end

  # ---------------------------------------------------------------------------
  # User.changeset/2 — validaciones del schema
  # ---------------------------------------------------------------------------

  describe "User.changeset/2" do
    test "válido con todos los campos requeridos" do
      changeset = User.changeset(%User{}, attrs_validos())
      assert changeset.valid?
    end

    test "inválido sin nombre" do
      changeset = User.changeset(%User{}, attrs_validos(%{name: nil}))
      refute changeset.valid?
      assert "no puede estar en blanco" in errors_on(changeset).name
    end

    test "inválido sin email" do
      changeset = User.changeset(%User{}, attrs_validos(%{email: nil}))
      refute changeset.valid?
      assert "no puede estar en blanco" in errors_on(changeset).email
    end

    test "inválido con email de formato incorrecto" do
      changeset = User.changeset(%User{}, attrs_validos(%{email: "no-es-email"}))
      refute changeset.valid?
      assert "tiene formato inválido" in errors_on(changeset).email
    end

    test "inválido sin contraseña al crear" do
      changeset = User.changeset(%User{}, attrs_validos(%{password: nil}))
      refute changeset.valid?
      assert "no puede estar en blanco" in errors_on(changeset).password
    end

    test "inválido con contraseña menor a 8 caracteres" do
      changeset = User.changeset(%User{}, attrs_validos(%{password: "corta"}))
      refute changeset.valid?
      assert "debe tener al menos 8 caracteres" in errors_on(changeset).password
    end

    test "inválido con rol desconocido" do
      changeset = User.changeset(%User{}, attrs_validos(%{role: "superheroe"}))
      refute changeset.valid?
      assert "no es una opción válida" in errors_on(changeset).role
    end

    test "empleado sin estaciones es inválido" do
      attrs = attrs_validos(%{role: "empleado", stations: []})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "debe asignarse al menos una estación" in errors_on(changeset).stations
    end

    test "empleado con una estación válida es válido" do
      for station <- ~w(cocina barra sala) do
        attrs = attrs_validos(%{role: "empleado", stations: [station]})
        changeset = User.changeset(%User{}, attrs)
        assert changeset.valid?, "esperaba válido con stations=[#{station}]"
      end
    end

    test "empleado con múltiples estaciones válidas es válido" do
      attrs = attrs_validos(%{role: "empleado", stations: ["barra", "sala"]})
      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "empleado con estación inválida es inválido" do
      attrs = attrs_validos(%{role: "empleado", stations: ["terraza"]})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert Enum.any?(errors_on(changeset).stations, &String.contains?(&1, "terraza"))
    end

    test "admin con estaciones — se limpian automáticamente" do
      attrs = attrs_validos(%{role: "admin", stations: ["cocina"]})
      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :stations) == []
    end

    test "cliente con estaciones — se limpian automáticamente" do
      attrs = attrs_validos(%{role: "cliente", stations: ["barra"]})
      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :stations) == []
    end

    test "la contraseña se guarda como hash y no en texto plano" do
      changeset = User.changeset(%User{}, attrs_validos())
      refute get_change(changeset, :password_hash) == "contraseña123"
      assert get_change(changeset, :password_hash) != nil
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.create_user/2
  # ---------------------------------------------------------------------------

  describe "create_user/2" do
    test "admin puede crear un usuario empleado" do
      admin = insertar_usuario()

      attrs = %{
        name: "Carlos Ruiz",
        email: "carlos@cafe.com",
        role: "empleado",
        stations: ["cocina"],
        password: "contraseña123"
      }

      assert {:ok, %User{name: "Carlos Ruiz", role: "empleado"}} =
               Accounts.create_user(admin, attrs)
    end

    test "admin puede crear otro admin" do
      admin = insertar_usuario()
      attrs = attrs_validos(%{email: "otro@cafe.com"})
      assert {:ok, %User{role: "admin"}} = Accounts.create_user(admin, attrs)
    end

    test "empleado no puede crear usuarios" do
      empleado =
        insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp@cafe.com"})

      attrs = attrs_validos(%{email: "nuevo@cafe.com"})
      assert {:error, :unauthorized} = Accounts.create_user(empleado, attrs)
    end

    test "cliente no puede crear usuarios" do
      cliente = insertar_usuario(%{role: "cliente", email: "cli@cafe.com"})
      attrs = attrs_validos(%{email: "nuevo@cafe.com"})
      assert {:error, :unauthorized} = Accounts.create_user(cliente, attrs)
    end

    test "email duplicado retorna error de changeset" do
      admin = insertar_usuario()
      attrs = attrs_validos(%{email: "ana@cafe.com"})
      assert {:error, changeset} = Accounts.create_user(admin, attrs)
      assert "ya está en uso" in errors_on(changeset).email
    end

    test "datos inválidos retornan error de changeset" do
      admin = insertar_usuario()
      assert {:error, changeset} = Accounts.create_user(admin, %{name: nil})
      assert errors_on(changeset).name
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.deactivate_user/2
  # ---------------------------------------------------------------------------

  describe "deactivate_user/2" do
    test "admin puede desactivar un usuario" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "emp@cafe.com"})

      assert {:ok, %User{is_active: false}} = Accounts.deactivate_user(admin, empleado)
    end

    test "empleado no puede desactivar usuarios" do
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp@cafe.com"})
      otro = insertar_usuario(%{role: "empleado", stations: ["cocina"], email: "otro@cafe.com"})

      assert {:error, :unauthorized} = Accounts.deactivate_user(empleado, otro)
    end

    test "admin no puede desactivarse a sí mismo" do
      admin = insertar_usuario()
      assert {:error, :cannot_deactivate_self} = Accounts.deactivate_user(admin, admin)
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.activate_user/2
  # ---------------------------------------------------------------------------

  describe "activate_user/2" do
    test "admin puede reactivar un usuario" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "emp@cafe.com"})
      {:ok, desactivado} = Accounts.deactivate_user(admin, empleado)

      assert {:ok, %User{is_active: true}} = Accounts.activate_user(admin, desactivado)
    end

    test "empleado no puede activar usuarios" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp@cafe.com"})
      {:ok, desactivado} = Accounts.deactivate_user(admin, empleado)

      otro_admin = insertar_usuario(%{email: "admin2@cafe.com"})
      assert {:error, :unauthorized} = Accounts.activate_user(desactivado, otro_admin)
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.list_users/0
  # ---------------------------------------------------------------------------

  describe "list_users/0" do
    test "retorna todos los usuarios ordenados por nombre" do
      insertar_usuario(%{name: "Zara", email: "zara@cafe.com"})
      insertar_usuario(%{name: "Ana López", email: "ana@cafe.com"})

      users = Accounts.list_users()
      nombres = Enum.map(users, & &1.name)
      assert nombres == Enum.sort(nombres)
    end

    test "incluye usuarios inactivos" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "emp@cafe.com"})
      Accounts.deactivate_user(admin, empleado)

      assert length(Accounts.list_users()) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.get_user!/1
  # ---------------------------------------------------------------------------

  describe "get_user!/1" do
    test "retorna el usuario por id" do
      user = insertar_usuario()
      assert Accounts.get_user!(user.id).id == user.id
    end

    test "lanza excepción si no existe" do
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(0) end
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.authenticate_user/2
  # ---------------------------------------------------------------------------

  describe "authenticate_user/2" do
    test "credenciales correctas retornan el usuario" do
      _user = insertar_usuario(%{email: "login@cafe.com"})
      assert {:ok, %User{email: "login@cafe.com"}} =
               Accounts.authenticate_user("login@cafe.com", "contraseña123")
    end

    test "contraseña incorrecta retorna error" do
      insertar_usuario(%{email: "login@cafe.com"})
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("login@cafe.com", "mal_password")
    end

    test "email inexistente retorna error" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("noexiste@cafe.com", "contraseña123")
    end

    test "usuario inactivo no puede autenticarse" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp@cafe.com"})
      Accounts.deactivate_user(admin, empleado)

      assert {:error, :inactive_user} =
               Accounts.authenticate_user("emp@cafe.com", "contraseña123")
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.update_user/3
  # ---------------------------------------------------------------------------

  describe "update_user/3" do
    test "admin puede actualizar nombre y estaciones" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp_upd@cafe.com"})

      assert {:ok, updated} =
               Accounts.update_user(admin, empleado, %{name: "Nuevo Nombre", stations: ["barra", "sala"]})

      assert updated.name == "Nuevo Nombre"
      assert "barra" in updated.stations
    end

    test "empleado no puede actualizar usuarios" do
      empleado = insertar_usuario(%{role: "empleado", stations: ["cocina"], email: "emp_upd2@cafe.com"})
      otro = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "otro_upd@cafe.com"})

      assert {:error, :unauthorized} =
               Accounts.update_user(empleado, otro, %{name: "Hackeado"})
    end

    test "retorna error con datos inválidos" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "emp_upd3@cafe.com"})

      assert {:error, %Ecto.Changeset{}} =
               Accounts.update_user(admin, empleado, %{email: "no-es-email"})
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.give_recognition/2
  # ---------------------------------------------------------------------------

  describe "give_recognition/2" do
    test "admin puede dar un reconocimiento a un empleado" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "rec_emp@cafe.com"})

      attrs = %{user_id: empleado.id, kind: "top_sales", period_date: Date.utc_today()}
      assert {:ok, rec} = Accounts.give_recognition(admin, attrs)
      assert rec.kind == "top_sales"
      assert rec.user_id == empleado.id
      assert rec.given_by_id == admin.id
    end

    test "admin puede incluir nota en el reconocimiento" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "rec_nota@cafe.com"})

      attrs = %{user_id: empleado.id, kind: "custom", note: "Excelente actitud", period_date: Date.utc_today()}
      assert {:ok, rec} = Accounts.give_recognition(admin, attrs)
      assert rec.note == "Excelente actitud"
    end

    test "empleado no puede dar reconocimientos" do
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "rec_unauth@cafe.com"})
      otro = insertar_usuario(%{role: "empleado", stations: ["cocina"], email: "rec_otro@cafe.com"})

      attrs = %{user_id: otro.id, kind: "top_speed", period_date: Date.utc_today()}
      assert {:error, :unauthorized} = Accounts.give_recognition(empleado, attrs)
    end

    test "retorna error con kind inválido" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "rec_inv@cafe.com"})

      attrs = %{user_id: empleado.id, kind: "invalido", period_date: Date.utc_today()}
      assert {:error, %Ecto.Changeset{}} = Accounts.give_recognition(admin, attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.list_recognitions_for_period/1
  # ---------------------------------------------------------------------------

  describe "list_recognitions_for_period/1" do
    test "retorna reconocimientos del día indicado" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "lrp@cafe.com"})

      today = Date.utc_today()
      Accounts.give_recognition(admin, %{user_id: empleado.id, kind: "top_speed", period_date: today})

      results = Accounts.list_recognitions_for_period(today)
      assert Enum.any?(results, &(&1.user_id == empleado.id))
    end

    test "no retorna reconocimientos de otra fecha" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "lrp2@cafe.com"})

      yesterday = Date.add(Date.utc_today(), -1)
      Accounts.give_recognition(admin, %{user_id: empleado.id, kind: "custom", period_date: yesterday})

      results = Accounts.list_recognitions_for_period(Date.utc_today())
      refute Enum.any?(results, &(&1.user_id == empleado.id))
    end

    test "precarga usuario y given_by" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "lrp3@cafe.com"})

      Accounts.give_recognition(admin, %{user_id: empleado.id, kind: "top_sales", period_date: Date.utc_today()})
      [rec | _] = Accounts.list_recognitions_for_period(Date.utc_today())

      assert rec.user.id == empleado.id
      assert rec.given_by.id == admin.id
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.list_recognitions_for_user/1
  # ---------------------------------------------------------------------------

  describe "list_recognitions_for_user/1" do
    test "retorna reconocimientos del usuario en los últimos 30 días" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "lru@cafe.com"})

      Accounts.give_recognition(admin, %{user_id: empleado.id, kind: "top_sales", period_date: Date.utc_today()})

      results = Accounts.list_recognitions_for_user(empleado.id)
      assert length(results) >= 1
    end

    test "no retorna reconocimientos de hace más de 30 días" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", stations: ["barra"], email: "lru2@cafe.com"})

      old_date = Date.add(Date.utc_today(), -31)
      Accounts.give_recognition(admin, %{user_id: empleado.id, kind: "custom", period_date: old_date})

      assert Accounts.list_recognitions_for_user(empleado.id) == []
    end

    test "no retorna reconocimientos de otro usuario" do
      admin = insertar_usuario()
      emp1 = insertar_usuario(%{role: "empleado", stations: ["sala"], email: "lru3a@cafe.com"})
      emp2 = insertar_usuario(%{role: "empleado", stations: ["cocina"], email: "lru3b@cafe.com"})

      Accounts.give_recognition(admin, %{user_id: emp1.id, kind: "top_speed", period_date: Date.utc_today()})

      assert Accounts.list_recognitions_for_user(emp2.id) == []
    end
  end
end
