# Seeds para Café Raíces y Cultura — menú real extraído del PDF del negocio
# Ejecutar con: mix run priv/repo/seeds.exs

alias CRC.Repo
alias CRC.Catalog.{Category, MenuItem}
alias CRC.Media.Photo

# ---------------------------------------------------------------------------
# Limpiar datos existentes
# ---------------------------------------------------------------------------
Repo.delete_all(MenuItem)
Repo.delete_all(Category)
Repo.delete_all(Photo)

# ---------------------------------------------------------------------------
# Categorías (basadas en el menú real)
# ---------------------------------------------------------------------------
categories =
  [
    %{name: "Café Filtrados",     slug: "cafe-filtrados",     kind: "drink", position: 1},
    %{name: "Sin Cafeína",        slug: "sin-cafeina",        kind: "drink", position: 2},
    %{name: "Oleos y Mocktails",  slug: "oleos-y-mocktails",  kind: "drink", position: 3},
    %{name: "Extras",             slug: "extras",             kind: "extra", position: 4},
    %{name: "Sanduíses",          slug: "sandwises",          kind: "food",  position: 5},
    %{name: "Pan Pizza",          slug: "pan-pizza",          kind: "food",  position: 6},
    %{name: "Para Almorzar",      slug: "para-almorzar",      kind: "food",  position: 7}
  ]
  |> Enum.map(fn attrs ->
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing)
  end)

category_map = Enum.reduce(categories, %{}, fn c, acc -> Map.put(acc, c.slug, c.id) end)

# ---------------------------------------------------------------------------
# Items de menú — precios y descripciones del PDF original
# ---------------------------------------------------------------------------
menu_items = [

  # ── Café Filtrados ────────────────────────────────────────────────────────
  %{
    name: "Espresso",
    description: "Extracción pura de nuestro blend. Intenso, equilibrado.",
    price: Decimal.new("40.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 1
  },
  %{
    name: "Americano",
    description: "Espresso suavizado con agua caliente. Largo y aromático.",
    price: Decimal.new("45.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 2
  },
  %{
    name: "Flat White",
    description: "Doble espresso con leche vaporizada suave y microespuma sedosa.",
    price: Decimal.new("50.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 3
  },
  %{
    name: "Cappuccino",
    description: "Espresso con leche vaporizada y espuma cremosa en proporciones perfectas.",
    price: Decimal.new("55.00"),
    category_id: category_map["cafe-filtrados"],
    featured: true,
    position: 4
  },
  %{
    name: "Latte",
    description: "Espresso generoso con leche vaporizada suave. Base perfecta para cualquier momento.",
    price: Decimal.new("55.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 5
  },
  %{
    name: "Café de Olla",
    description: "Café de filtrado artesanal con canela y piloncillo. Sabor de raíces.",
    price: Decimal.new("55.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 6
  },
  %{
    name: "Matcha Culinario",
    description: "Matcha con leche vaporizada. Suave, verde y reconfortante.",
    price: Decimal.new("65.00"),
    category_id: category_map["cafe-filtrados"],
    featured: true,
    position: 7
  },
  %{
    name: "Chocolate",
    description: "Cacao artesanal con leche entera. Espeso y de sabor profundo.",
    price: Decimal.new("65.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 8
  },
  %{
    name: "Mocca",
    description: "Espresso con chocolate y leche vaporizada. El mejor de dos mundos.",
    price: Decimal.new("75.00"),
    category_id: category_map["cafe-filtrados"],
    featured: false,
    position: 9
  },

  # ── Sin Cafeína ───────────────────────────────────────────────────────────
  %{
    name: "Earl Grey",
    description: "Té negro con bergamota. Clásico, delicado y aromático.",
    price: Decimal.new("60.00"),
    category_id: category_map["sin-cafeina"],
    featured: false,
    position: 1
  },
  %{
    name: "Cúrcuma y Jengibre",
    description: "Infusión cálida con cúrcuma fresca y jengibre. Antiinflamatoria y reconfortante.",
    price: Decimal.new("60.00"),
    category_id: category_map["sin-cafeina"],
    featured: false,
    position: 2
  },
  %{
    name: "Masala Chai",
    description: "Blend de especias indias con leche vegetal. Especiado y envolvente.",
    price: Decimal.new("60.00"),
    category_id: category_map["sin-cafeina"],
    featured: true,
    position: 3
  },
  %{
    name: "Tisana Frutos Rojos",
    description: "Infusión frutal de frutos rojos. Sin cafeína, llena de color y sabor.",
    price: Decimal.new("60.00"),
    category_id: category_map["sin-cafeina"],
    featured: false,
    position: 4
  },
  %{
    name: "Grano Nacional — Atlixco de las Flores",
    description: "Café filtrado de origen Atlixco de las Flores, Puebla. Notas dulces y florales.",
    price: Decimal.new("65.00"),
    category_id: category_map["sin-cafeina"],
    featured: true,
    position: 5
  },
  %{
    name: "Cafecito Internacional",
    description: "Selección de granos de origen único de distintas partes del mundo.",
    price: Decimal.new("85.00"),
    category_id: category_map["sin-cafeina"],
    featured: false,
    position: 6
  },

  # ── Oleos y Mocktails ─────────────────────────────────────────────────────
  %{
    name: "Cold Brew",
    description: "Infusión en frío de 18 horas. Suave, con cuerpo y sin acidez.",
    price: Decimal.new("55.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: true,
    position: 1
  },
  %{
    name: "Limonada Clásica",
    description: "Limón amarillo, agua mineral y un toque de miel. Refrescante y natural.",
    price: Decimal.new("60.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 2
  },
  %{
    name: "Limonada Frutos Silvestres",
    description: "Limonada con mezcla de frutos silvestres de temporada.",
    price: Decimal.new("60.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 3
  },
  %{
    name: "Limonada Rosa",
    description: "Limonada con toque de frutos rojos y agua mineral. Floral y refrescante.",
    price: Decimal.new("60.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: true,
    position: 4
  },
  %{
    name: "Espresso Tonic",
    description: "Doble espresso sobre agua tónica con hielo. Amargo, burbujeante y vibrante.",
    price: Decimal.new("60.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 5
  },
  %{
    name: "Smoothie Frutal",
    description: "Mezcla de frutas frescas de temporada. Espeso, natural y sin azúcar añadida.",
    price: Decimal.new("65.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 6
  },
  %{
    name: "Citric Brew",
    description: "Cold brew con cítricos frescos. Intenso, ácido y muy refrescante.",
    price: Decimal.new("70.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 7
  },
  %{
    name: "Jamaica Brew",
    description: "Cold brew con infusión de jamaica. Frutal, rojo y profundo.",
    price: Decimal.new("75.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 8
  },
  %{
    name: "Torito",
    description: "Bebida fresca de inspiración veracruzana con cacahuate y vainilla.",
    price: Decimal.new("80.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: false,
    position: 9
  },
  %{
    name: "De Temporada",
    description: "Creación especial del barista con ingredientes de temporada. Pregunta por la del día.",
    price: Decimal.new("85.00"),
    category_id: category_map["oleos-y-mocktails"],
    featured: true,
    position: 10
  },

  # ── Extras ────────────────────────────────────────────────────────────────
  %{
    name: "Leche Vegetal",
    description: "Avena, almendra o soya. Pregunta disponibilidad.",
    price: Decimal.new("15.00"),
    category_id: category_map["extras"],
    featured: false,
    position: 1
  },
  %{
    name: "Carga de Espresso",
    description: "Shot extra de espresso para tu bebida.",
    price: Decimal.new("15.00"),
    category_id: category_map["extras"],
    featured: false,
    position: 2
  },
  %{
    name: "Vaso de Leche",
    description: "Leche entera fría o caliente.",
    price: Decimal.new("25.00"),
    category_id: category_map["extras"],
    featured: false,
    position: 3
  },

  # ── Sanduíses ─────────────────────────────────────────────────────────────
  %{
    name: "Vegetariano",
    description: "Champis, chile morrón, queso gouda, tomate cherry y pepinillos.",
    price: Decimal.new("85.00"),
    category_id: category_map["sandwises"],
    featured: false,
    position: 1
  },
  %{
    name: "Clásico",
    description: "Pechuga de pavo, tomate cherry y arugula.",
    price: Decimal.new("95.00"),
    category_id: category_map["sandwises"],
    featured: false,
    position: 2
  },
  %{
    name: "Grilled Cheese",
    description: "Mezcla de quesos artesanales y salsa pomodoro casera.",
    price: Decimal.new("95.00"),
    category_id: category_map["sandwises"],
    featured: false,
    position: 3
  },
  %{
    name: "El Exótico",
    description: "Chistorra, queso gouda, cebolla caramelizada, cherrys sofritos, arugula y dip de aguacate.",
    price: Decimal.new("110.00"),
    category_id: category_map["sandwises"],
    featured: false,
    position: 4
  },
  %{
    name: "El Favorito",
    description: "Arrachera, queso gouda, dip de aguacate, tomate cherry, champis, morrón y arugula.",
    price: Decimal.new("115.00"),
    category_id: category_map["sandwises"],
    featured: true,
    position: 5
  },

  # ── Pan Pizza ─────────────────────────────────────────────────────────────
  %{
    name: "Sencilla",
    description: "Queso gouda, salsa de tomate y finas hierbas.",
    price: Decimal.new("75.00"),
    category_id: category_map["pan-pizza"],
    featured: false,
    position: 1
  },
  %{
    name: "Vegetariano",
    description: "Champis, chile morrón, queso gouda, tomate cherry y arugula.",
    price: Decimal.new("80.00"),
    category_id: category_map["pan-pizza"],
    featured: false,
    position: 2
  },
  %{
    name: "Quesos",
    description: "Salsa de tomate, finas hierbas y generosa mezcla de quesos.",
    price: Decimal.new("85.00"),
    category_id: category_map["pan-pizza"],
    featured: true,
    position: 3
  },
  %{
    name: "El Viejo y Confiable",
    description: "Salsa de tomate, pepperoni y queso gouda. El clásico de siempre.",
    price: Decimal.new("85.00"),
    category_id: category_map["pan-pizza"],
    featured: false,
    position: 4
  },
  %{
    name: "El Mexa",
    description: "Salsa de tomate, frijoles, jalapeño, chistorra, queso gouda, cebolla morada y champis.",
    price: Decimal.new("95.00"),
    category_id: category_map["pan-pizza"],
    featured: true,
    position: 5
  },

  # ── Para Almorzar ─────────────────────────────────────────────────────────
  %{
    name: "Pan Tostado Mexa",
    description: "Dos rebanadas de pan campesino con miel, azúcar, fruta y jalea.",
    price: Decimal.new("50.00"),
    category_id: category_map["para-almorzar"],
    featured: false,
    position: 1
  },
  %{
    name: "Fruta de Temporada",
    description: "Fruta picada de temporada, quesos y arugula, acompañada con yoghurt, miel y granola.",
    price: Decimal.new("55.00"),
    category_id: category_map["para-almorzar"],
    featured: false,
    position: 2
  },
  %{
    name: "Avena Trasnochada",
    description: "Avena suave remojada en leche con toque dulce, fruta de temporada y semillas.",
    price: Decimal.new("65.00"),
    category_id: category_map["para-almorzar"],
    featured: false,
    position: 3
  },
  %{
    name: "Toast Francés",
    description: "Pan campesino suave y dulce con crema de avellanas, fruta fresca y miel.",
    price: Decimal.new("95.00"),
    category_id: category_map["para-almorzar"],
    featured: true,
    position: 4
  }
]

Enum.each(menu_items, fn attrs ->
  %MenuItem{}
  |> MenuItem.changeset(attrs)
  |> Repo.insert!()
end)

# ---------------------------------------------------------------------------
# Fotos placeholder (Unsplash — se reemplazan con fotos reales del café)
# ---------------------------------------------------------------------------
photos = [
  %{
    url: "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=1600&auto=format&fit=crop",
    caption: "Bienvenidos a Café Raíces y Cultura",
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
    caption: "Tu lugar favorito en Lindavista",
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

IO.puts("✓ Seeds completados: #{length(categories)} categorías, #{length(menu_items)} items de menú, #{length(photos)} fotos.")
