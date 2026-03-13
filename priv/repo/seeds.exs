# Seeds for Café Raíces y Cultura
# Run with: mix run priv/repo/seeds.exs

alias CRC.Repo
alias CRC.Catalog.{Category, MenuItem}
alias CRC.Media.Photo

# ---------------------------------------------------------------------------
# Clean existing seed data
# ---------------------------------------------------------------------------
Repo.delete_all(MenuItem)
Repo.delete_all(Category)
Repo.delete_all(Photo)

# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------
categories =
  [
    %{name: "Cafés de Especialidad", slug: "cafes-de-especialidad", kind: "drink", position: 1},
    %{name: "Bebidas Frías", slug: "bebidas-frias", kind: "drink", position: 2},
    %{name: "Desayunos", slug: "desayunos", kind: "food", position: 3},
    %{name: "Antojitos", slug: "antojitos", kind: "food", position: 4},
    %{name: "Postres", slug: "postres", kind: "food", position: 5}
  ]
  |> Enum.map(fn attrs ->
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing)
  end)

category_map = Enum.reduce(categories, %{}, fn c, acc -> Map.put(acc, c.slug, c.id) end)

# ---------------------------------------------------------------------------
# Menu Items
# ---------------------------------------------------------------------------
menu_items = [
  # Cafés de Especialidad
  %{
    name: "Espresso",
    description: "Extracción pura de nuestro blend de origen único, intenso y equilibrado.",
    price: Decimal.new("55.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: true,
    position: 1
  },
  %{
    name: "Americano",
    description: "Espresso suavizado con agua caliente para un café largo y aromático.",
    price: Decimal.new("60.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: false,
    position: 2
  },
  %{
    name: "Cappuccino",
    description: "Espresso con leche vaporizada y espuma cremosa en proporciones perfectas.",
    price: Decimal.new("75.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: true,
    position: 3
  },
  %{
    name: "Latte",
    description: "Espresso generoso con leche vaporizada suave. Base perfecta para sabores.",
    price: Decimal.new("80.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: false,
    position: 4
  },
  %{
    name: "Pour Over",
    description: "Método de filtrado manual que resalta las notas florales y frutales del grano.",
    price: Decimal.new("90.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: true,
    position: 5
  },
  %{
    name: "Cortado",
    description: "Espresso cortado con una pequeña cantidad de leche para balancear la acidez.",
    price: Decimal.new("65.00"),
    category_id: category_map["cafes-de-especialidad"],
    featured: false,
    position: 6
  },
  # Bebidas Frías
  %{
    name: "Cold Brew",
    description: "Infusión fría de 16 horas. Suave, con cuerpo y sin amargura.",
    price: Decimal.new("85.00"),
    category_id: category_map["bebidas-frias"],
    featured: true,
    position: 1
  },
  %{
    name: "Frappé de Café",
    description: "Cold brew batido con leche, hielo y un toque de vainilla.",
    price: Decimal.new("95.00"),
    category_id: category_map["bebidas-frias"],
    featured: false,
    position: 2
  },
  %{
    name: "Matcha Latte Frío",
    description: "Té matcha ceremonial japonés con leche de avena y hielo.",
    price: Decimal.new("90.00"),
    category_id: category_map["bebidas-frias"],
    featured: false,
    position: 3
  },
  %{
    name: "Limonada de Hierbabuena",
    description: "Limón amarillo, hierbabuena fresca y agua mineral. Refrescante y natural.",
    price: Decimal.new("70.00"),
    category_id: category_map["bebidas-frias"],
    featured: false,
    position: 4
  },
  # Desayunos
  %{
    name: "Tostadas Francesas",
    description: "Pan brioche bañado en huevo, canela y piloncillo. Con frutos del bosque y crema.",
    price: Decimal.new("120.00"),
    category_id: category_map["desayunos"],
    featured: true,
    position: 1
  },
  %{
    name: "Chilaquiles Verdes",
    description: "Totopos en salsa verde tatemada, crema, queso fresco y dos huevos al gusto.",
    price: Decimal.new("130.00"),
    category_id: category_map["desayunos"],
    featured: true,
    position: 2
  },
  %{
    name: "Bowl de Granola",
    description: "Granola artesanal con yogur griego, miel de abeja y fruta de temporada.",
    price: Decimal.new("110.00"),
    category_id: category_map["desayunos"],
    featured: false,
    position: 3
  },
  %{
    name: "Molletes con Pico",
    description: "Pan bolillo con frijoles refritos, queso manchego gratinado y pico de gallo.",
    price: Decimal.new("100.00"),
    category_id: category_map["desayunos"],
    featured: false,
    position: 4
  },
  # Antojitos
  %{
    name: "Tlayuda",
    description: "Tortilla tostada con frijoles negros, quesillo, tasajo y chapulines.",
    price: Decimal.new("115.00"),
    category_id: category_map["antojitos"],
    featured: false,
    position: 1
  },
  %{
    name: "Quesadillas de Huitlacoche",
    description: "Tortilla de maíz azul con huitlacoche, epazote y quesillo oaxaqueño.",
    price: Decimal.new("105.00"),
    category_id: category_map["antojitos"],
    featured: true,
    position: 2
  },
  %{
    name: "Tostadas de Tinga",
    description: "Tinga de pollo con chipotle, lechuga, crema y queso cotija. (2 piezas)",
    price: Decimal.new("95.00"),
    category_id: category_map["antojitos"],
    featured: false,
    position: 3
  },
  # Postres
  %{
    name: "Pastel de Tres Leches",
    description: "Bizcocho esponjoso empapado en tres leches, cubierto con crema batida.",
    price: Decimal.new("85.00"),
    category_id: category_map["postres"],
    featured: true,
    position: 1
  },
  %{
    name: "Brownie con Helado",
    description: "Brownie tibio de chocolate amargo con bola de helado de vainilla.",
    price: Decimal.new("95.00"),
    category_id: category_map["postres"],
    featured: false,
    position: 2
  },
  %{
    name: "Flan Napolitano",
    description: "Flan casero con cajeta y nuez. Receta de la casa.",
    price: Decimal.new("75.00"),
    category_id: category_map["postres"],
    featured: false,
    position: 3
  }
]

Enum.each(menu_items, fn attrs ->
  %MenuItem{}
  |> MenuItem.changeset(attrs)
  |> Repo.insert!()
end)

# ---------------------------------------------------------------------------
# Photos (Unsplash placeholder URLs for coffee shop)
# ---------------------------------------------------------------------------
photos = [
  %{
    url: "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=1600&auto=format&fit=crop",
    caption: "El corazón de Raíces y Cultura",
    position: 1
  },
  %{
    url: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=1600&auto=format&fit=crop",
    caption: "Cafés de especialidad preparados con amor",
    position: 2
  },
  %{
    url: "https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=1600&auto=format&fit=crop",
    caption: "Cada taza cuenta una historia",
    position: 3
  },
  %{
    url: "https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=1600&auto=format&fit=crop",
    caption: "Nuestro espacio, tu lugar favorito",
    position: 4
  },
  %{
    url: "https://images.unsplash.com/photo-1521017432531-fbd92d768814?w=1600&auto=format&fit=crop",
    caption: "Sabores que nos conectan con nuestras raíces",
    position: 5
  }
]

Enum.each(photos, fn attrs ->
  %Photo{}
  |> Photo.changeset(attrs)
  |> Repo.insert!()
end)

IO.puts("Seeds completados: categorias, items de menu y fotos de placeholder.")
