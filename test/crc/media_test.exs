defmodule CRC.MediaTest do
  use CRC.DataCase, async: true

  alias CRC.Media
  alias CRC.Media.Photo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp photo_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        url: "https://example.com/foto.jpg",
        caption: "Una foto de prueba",
        position: 0,
        active: true
      },
      overrides
    )
  end

  defp insert_photo(overrides \\ %{}) do
    {:ok, photo} = Media.create_photo(photo_attrs(overrides))
    photo
  end

  # ===========================================================================
  # Photo.changeset/2
  # ===========================================================================

  describe "Photo.changeset/2" do
    test "válido con url" do
      changeset = Photo.changeset(%Photo{}, photo_attrs())
      assert changeset.valid?
    end

    test "inválido sin url" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{url: nil}))
      refute changeset.valid?
      assert changeset.errors[:url]
    end

    test "inválido con url sin protocolo ni slash" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{url: "example.com/foto.jpg"}))
      refute changeset.valid?
      assert changeset.errors[:url]
    end

    test "válido con url https" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{url: "https://cdn.example.com/img.jpg"}))
      assert changeset.valid?
    end

    test "válido con url http" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{url: "http://example.com/img.jpg"}))
      assert changeset.valid?
    end

    test "válido con path local (empieza con /)" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{url: "/images/foto.jpg"}))
      assert changeset.valid?
    end

    test "caption es opcional" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{caption: nil}))
      assert changeset.valid?
    end

    test "position es opcional y tiene default 0" do
      changeset = Photo.changeset(%Photo{}, photo_attrs(%{position: nil}))
      assert changeset.valid?
    end

    test "active es opcional y tiene default true" do
      {:ok, photo} = Media.create_photo(Map.delete(photo_attrs(), :active))
      assert photo.active == true
    end
  end

  # ===========================================================================
  # list_photos/0
  # ===========================================================================

  describe "list_photos/0" do
    test "retorna solo fotos activas" do
      insert_photo(%{url: "https://example.com/activa.jpg", active: true})
      insert_photo(%{url: "https://example.com/inactiva.jpg", active: false})

      photos = Media.list_photos()
      urls = Enum.map(photos, & &1.url)

      assert "https://example.com/activa.jpg" in urls
      refute "https://example.com/inactiva.jpg" in urls
    end

    test "retorna fotos ordenadas por position" do
      insert_photo(%{url: "https://example.com/c.jpg", position: 3})
      insert_photo(%{url: "https://example.com/a.jpg", position: 1})
      insert_photo(%{url: "https://example.com/b.jpg", position: 2})

      photos = Media.list_photos()
      positions = Enum.map(photos, & &1.position)
      assert positions == Enum.sort(positions)
    end
  end

  # ===========================================================================
  # list_all_photos/0
  # ===========================================================================

  describe "list_all_photos/0" do
    test "retorna todas las fotos incluyendo inactivas" do
      insert_photo(%{url: "https://example.com/activa2.jpg", active: true})
      insert_photo(%{url: "https://example.com/inactiva2.jpg", active: false})

      photos = Media.list_all_photos()
      urls = Enum.map(photos, & &1.url)

      assert "https://example.com/activa2.jpg" in urls
      assert "https://example.com/inactiva2.jpg" in urls
    end
  end

  # ===========================================================================
  # get_photo!/1
  # ===========================================================================

  describe "get_photo!/1" do
    test "retorna la foto por id" do
      photo = insert_photo()
      assert Media.get_photo!(photo.id).id == photo.id
    end

    test "lanza excepción si no existe" do
      assert_raise Ecto.NoResultsError, fn -> Media.get_photo!(0) end
    end
  end

  # ===========================================================================
  # create_photo/1
  # ===========================================================================

  describe "create_photo/1" do
    test "crea foto con datos válidos" do
      assert {:ok, %Photo{url: "https://example.com/foto.jpg"}} =
               Media.create_photo(photo_attrs())
    end

    test "falla sin url" do
      assert {:error, %Ecto.Changeset{}} = Media.create_photo(%{caption: "sin url"})
    end
  end

  # ===========================================================================
  # update_photo/2
  # ===========================================================================

  describe "update_photo/2" do
    test "actualiza la foto exitosamente" do
      photo = insert_photo()
      assert {:ok, updated} = Media.update_photo(photo, %{caption: "Nuevo pie de foto"})
      assert updated.caption == "Nuevo pie de foto"
    end

    test "falla con url inválida" do
      photo = insert_photo()
      assert {:error, %Ecto.Changeset{}} = Media.update_photo(photo, %{url: "invalida"})
    end
  end

  # ===========================================================================
  # delete_photo/1
  # ===========================================================================

  describe "delete_photo/1" do
    test "elimina la foto exitosamente" do
      photo = insert_photo()
      assert {:ok, _deleted} = Media.delete_photo(photo)
      assert_raise Ecto.NoResultsError, fn -> Media.get_photo!(photo.id) end
    end
  end
end
