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

    test "empleado sin estación es inválido" do
      attrs = attrs_validos(%{role: "empleado", station: nil})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "no puede estar en blanco" in errors_on(changeset).station
    end

    test "empleado con estación válida es válido" do
      for station <- ~w(cocina barra sala) do
        attrs = attrs_validos(%{role: "empleado", station: station})
        changeset = User.changeset(%User{}, attrs)
        assert changeset.valid?, "esperaba válido con station=#{station}"
      end
    end

    test "empleado con estación inválida es inválido" do
      attrs = attrs_validos(%{role: "empleado", station: "terraza"})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "no es una opción válida" in errors_on(changeset).station
    end

    test "admin con estación es inválido" do
      attrs = attrs_validos(%{role: "admin", station: "cocina"})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "debe estar en blanco para este rol" in errors_on(changeset).station
    end

    test "cliente con estación es inválido" do
      attrs = attrs_validos(%{role: "cliente", station: "barra"})
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "debe estar en blanco para este rol" in errors_on(changeset).station
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
        station: "cocina",
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
        insertar_usuario(%{role: "empleado", station: "sala", email: "emp@cafe.com"})

      attrs = attrs_validos(%{email: "nuevo@cafe.com"})
      assert {:error, :no_autorizado} = Accounts.create_user(empleado, attrs)
    end

    test "cliente no puede crear usuarios" do
      cliente = insertar_usuario(%{role: "cliente", email: "cli@cafe.com"})
      attrs = attrs_validos(%{email: "nuevo@cafe.com"})
      assert {:error, :no_autorizado} = Accounts.create_user(cliente, attrs)
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
      empleado = insertar_usuario(%{role: "empleado", station: "barra", email: "emp@cafe.com"})

      assert {:ok, %User{is_active: false}} = Accounts.deactivate_user(admin, empleado)
    end

    test "empleado no puede desactivar usuarios" do
      empleado = insertar_usuario(%{role: "empleado", station: "sala", email: "emp@cafe.com"})
      otro = insertar_usuario(%{role: "empleado", station: "cocina", email: "otro@cafe.com"})

      assert {:error, :no_autorizado} = Accounts.deactivate_user(empleado, otro)
    end

    test "admin no puede desactivarse a sí mismo" do
      admin = insertar_usuario()
      assert {:error, :no_puede_desactivarse_a_si_mismo} = Accounts.deactivate_user(admin, admin)
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts.activate_user/2
  # ---------------------------------------------------------------------------

  describe "activate_user/2" do
    test "admin puede reactivar un usuario" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", station: "barra", email: "emp@cafe.com"})
      {:ok, desactivado} = Accounts.deactivate_user(admin, empleado)

      assert {:ok, %User{is_active: true}} = Accounts.activate_user(admin, desactivado)
    end

    test "empleado no puede activar usuarios" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", station: "sala", email: "emp@cafe.com"})
      {:ok, desactivado} = Accounts.deactivate_user(admin, empleado)

      otro_admin = insertar_usuario(%{email: "admin2@cafe.com"})
      assert {:error, :no_autorizado} = Accounts.activate_user(desactivado, otro_admin)
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
      empleado = insertar_usuario(%{role: "empleado", station: "barra", email: "emp@cafe.com"})
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
      assert {:error, :credenciales_invalidas} =
               Accounts.authenticate_user("login@cafe.com", "mal_password")
    end

    test "email inexistente retorna error" do
      assert {:error, :credenciales_invalidas} =
               Accounts.authenticate_user("noexiste@cafe.com", "contraseña123")
    end

    test "usuario inactivo no puede autenticarse" do
      admin = insertar_usuario()
      empleado = insertar_usuario(%{role: "empleado", station: "sala", email: "emp@cafe.com"})
      Accounts.deactivate_user(admin, empleado)

      assert {:error, :usuario_inactivo} =
               Accounts.authenticate_user("emp@cafe.com", "contraseña123")
    end
  end
end
