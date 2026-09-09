defmodule CRC.Repo.Migrations.CleanUpMenuText do
  @moduledoc """
  Data migration: ortografía y estilo de nombres y descripciones del menú.

  Solo correcciones mecánicas (mayúscula inicial, acentos, typos claros,
  espacios/saltos de línea sobrantes, `iso`→`ISO`, `pelicula`→`película`,
  `tugsteno`→`tungsteno`, RemJet consistente). No se cambia el contenido ni
  los ingredientes de ningún platillo. La categoría "Sanduises" y ese estilo
  de nombres se dejan tal cual (es como CRC los llama).

  Irreversible por diseño: `down/0` no restaura los textos originales.
  """
  use Ecto.Migration

  # {id, nombre_nuevo | nil, descripción_nueva | nil}
  @changes [
    # ── Nombres con errores ────────────────────────────────────────────────
    {4, "Capuchino", "Espresso + leche cremada."},
    {9, "Affogato", "2 bolas de helado y espresso."},
    {23, "Smoothie", "Base agua.\n- Frutos rojos\n- Maracuyá\n- Piña colada"},
    {28, "El Favorito",
     "Pan de hogaza\nArrachera\nQueso gouda\nDip de aguacate\nTomate cherry\nChampiñones\nMorrón\nArúgula"},
    {29, "El Exótico",
     "Pan de hogaza\nChistorra\nQueso gouda\nCebolla caramelizada\nCherrys sofritos\nArúgula\nDip de aguacate"},
    {70, "Shanghai GP3", "Película en blanco y negro, ISO 100."},
    {78, "Masala Chai", "Concentrado ayurveda."},
    {83, "Molletes CRC",
     "4 clásicos medios panecillos, crema de frijoles, gouda y pechuga de pavo."},
    {98, "Extra Proteína", "Carne roja."},
    {104, "Óleo Piña Jengibre", nil},
    {8, "Café De Olla",
     "Espresso con el tradicional toque de concentrado de olla.\nDulce, tradicional y exquisito."},

    # ── Solo descripción ──────────────────────────────────────────────────
    {3, nil, "Espresso + agua caliente."},
    {5, nil, "Espresso + 4 oz de leche cremada."},
    {6, nil, "Mitad de espresso + leche cremada.\nBebida dulce y cremosa."},
    {10, nil,
     "Método de extracción con un grano nacional de tu elección.\nKalita, Chemex o V60."},
    {11, nil,
     "Método de extracción con un grano internacional de tu elección.\nKalita, Chemex o V60."},
    {12, nil,
     "- Atixco de las flores\n- Earl Grey\n- Cúrcuma Jengibre\n- Masala Chai\n- Tisana de frutos rojos"},
    {13, nil, "Matcha culinario japonés."},
    {14, nil, "Chocolate tradicional dulce\nadicionado con canela."},
    {15, nil, "Óleo de cítricos, con agua tónica y cold brew."},
    {16, nil, "Extracción de café en frío de 12 horas."},
    {17, nil, "Espresso y agua tónica."},
    {18, nil, "Reducción de jamaica con frutos rojos, agua tónica y cold brew."},
    {19, nil, "Óleo de toronja y frambuesa, con agua tónica y cold brew."},
    {20, nil, "Óleo cítrico, con agua tónica y matcha."},
    {22, nil, "Opción fresca y burbujeante.\n- Clásica\n- Limonada rosa\n- Tropical"},
    {24, nil, "Base de helado, leche y el sabor de tu elección."},
    {25, nil,
     "Pan de hogaza\nPechuga de pavo y queso\nAcompañado con jitomate cherry, champiñones y arúgula"},
    {26, nil,
     "Totopos fritos bañados en salsa verde con queso, crema y cebolla morada, acompañados con arrachera y una rebanada de pan campesino."},
    {30, nil,
     "250 g de fruta de temporada, picada y fresca, con miel, yogur natural, granola y semillas dulces."},
    {32, nil,
     "2 clásicos panecillos dorados con mantequilla, azúcar caramelizada, fruta picada y una bola de helado."},
    {33, nil,
     "Totopos fritos bañados en salsa verde, con crema, queso y cebolla morada.\nAcompañados con chistorra y una rebanada de pan campesino."},
    {34, nil,
     "Totopos fritos bañados en salsa verde, con crema, queso y cebolla morada.\nAcompañados con huevo revuelto y una rebanada de pan campesino."},
    {35, nil,
     "3 sopecitos con lechuga, crema, queso, cilantro y cebolla.\nAcompañados con huevo revuelto y salsa macha."},
    {36, nil,
     "3 sopecitos con lechuga, crema, queso y cebolla.\nAcompañados con chistorra y salsa macha."},
    {37, nil,
     "3 sopecitos con crema, queso y lechuga.\nAcompañados con arrachera y salsa macha."},
    {41, nil, "Servicio completo de revelado y escaneado de película de 35 mm en calidad alta."},
    {42, nil,
     "Servicio completo de revelado y escaneado de película con RemJet, proceso ECN2, en calidad alta."},
    {45, nil, "Leche regular, deslactosada o avena."},
    {55, nil, "ISO 50, luz de día."},
    {56, nil, "ISO 100, luz de día."},
    {57, nil, "Película en blanco y negro, ISO 400."},
    {58, nil, "Película sin RemJet, ISO 400, luz tungsteno."},
    {59, nil, "Película sin RemJet, ISO 800, luz tungsteno."},
    {60, nil, "Película sin RemJet, ISO 400, luz de día."},
    {61, nil, "Película sin RemJet, ISO 50, luz tungsteno."},
    {62, nil, "Película de cine con RemJet, ISO 200, luz tungsteno."},
    {63, nil, "Película de cine con RemJet, ISO 200, para luz de día."},
    {64, nil, "Película de cine con RemJet, ISO 500, luz tungsteno."},
    {65, nil, "Película ISO 200, luz de día."},
    {66, nil, "Película fotográfica en blanco y negro, ISO 400."},
    {67, nil, "Película fotográfica en blanco y negro, ISO 100."},
    {68, nil, "Película a color, ISO 100."},
    {69, nil, "Película de cine sin RemJet, ISO nominal 250."},
    {71, nil, "Película de cine para cruzar el proceso en blanco y negro, ISO 100."},
    {72, nil, "Película en blanco y negro, ISO 400."},
    {77, nil, "Por pieza."},
    {81, nil, "Mezcla de gouda y manchego, sobre una cama de salsa pomodoro y papitas."},
    {82, nil, "Totopos bañados en salsa verde, gouda, crema, cebolla, aguacate y pan campesino."},
    {84, nil, "Panqué de limón con semillas de amapola y azúcar glass."},
    {85, nil, "Deliciosa y suave mantecada de chocolate con cacao."},
    {86, nil, "Chino de vainilla y nuez."},
    {92, nil, "100 g de galleta."},
    {93, nil, "Cartucho de fotos instantáneas."},
    {94, nil, "De plátano con chocolate, o zanahoria con nuez."}
  ]

  def up do
    for {id, name, desc} <- @changes do
      {set, params} =
        cond do
          name && desc -> {"name = $1, description = $2", [name, desc, id]}
          name -> {"name = $1", [name, id]}
          true -> {"description = $1", [desc, id]}
        end

      idx = length(params)

      repo().query!(
        "UPDATE menu_items SET #{set}, updated_at = now() WHERE id = $#{idx}",
        params
      )
    end
  end

  def down, do: :ok
end
