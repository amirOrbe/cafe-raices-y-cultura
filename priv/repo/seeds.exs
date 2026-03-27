# Seeds para Café Raíces y Cultura — menú real extraído del PDF del negocio
# Ejecutar con: mix run priv/repo/seeds.exs

alias CRC.Repo
alias CRC.Accounts.User
alias CRC.Catalog.{Category, MenuItem, MenuItemIngredient}
alias CRC.Inventory.Product
alias CRC.Media.Photo
alias CRC.Orders.{Order, OrderItem}

# ---------------------------------------------------------------------------
# Limpiar datos existentes (respetando FK: hijos primero)
# ---------------------------------------------------------------------------
Repo.delete_all(MenuItemIngredient)
Repo.delete_all(OrderItem)
Repo.delete_all(Order)
Repo.delete_all(MenuItem)
Repo.delete_all(Category)
Repo.delete_all(Photo)
Repo.delete_all(User)
Repo.delete_all(Product)

# ---------------------------------------------------------------------------
# Usuario administrador inicial
# ---------------------------------------------------------------------------
%User{}
|> User.changeset(%{
  name: "Administrador",
  email: "admin@caferaices.mx",
  password: "12345678",
  role: "admin"
})
|> Repo.insert!()

%User{}
|> User.changeset(%{
  name: "Mesero",
  email: "mesero@caferaices.mx",
  password: "12345678",
  role: "empleado",
  station: "sala"
})
|> Repo.insert!()

IO.puts("✓ Usuarios creados:")
IO.puts("  admin@caferaices.mx   / 12345678  (admin)")
IO.puts("  mesero@caferaices.mx  / 12345678  (empleado)")

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

inserted_items =
  Enum.map(menu_items, fn attrs ->
    %MenuItem{}
    |> MenuItem.changeset(attrs)
    |> Repo.insert!()
  end)

item_map = Map.new(inserted_items, fn i -> {i.name, i.id} end)

# ---------------------------------------------------------------------------
# Ingredientes — productos sin proveedor (insumos internos del café)
# ---------------------------------------------------------------------------
ingredient_defs = [
  # ── Granos ──────────────────────────────────────────────────────────────
  %{name: "Granos de café blend",       category: "granos",    unit: "gramos",      net_cost: Decimal.new("0.60"), stock_quantity: Decimal.new("3000"),  min_stock: Decimal.new("500")},

  # ── Lácteos ─────────────────────────────────────────────────────────────
  %{name: "Leche entera",               category: "lacteos",   unit: "mililitros",  net_cost: Decimal.new("0.03"), stock_quantity: Decimal.new("10000"), min_stock: Decimal.new("2000")},
  %{name: "Leche de avena",             category: "lacteos",   unit: "mililitros",  net_cost: Decimal.new("0.06"), stock_quantity: Decimal.new("5000"),  min_stock: Decimal.new("1000")},
  %{name: "Leche de almendra",          category: "lacteos",   unit: "mililitros",  net_cost: Decimal.new("0.07"), stock_quantity: Decimal.new("3000"),  min_stock: Decimal.new("500")},
  %{name: "Leche de soya",              category: "lacteos",   unit: "mililitros",  net_cost: Decimal.new("0.05"), stock_quantity: Decimal.new("3000"),  min_stock: Decimal.new("500")},
  %{name: "Yoghurt natural",            category: "lacteos",   unit: "gramos",      net_cost: Decimal.new("0.08"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("500")},
  %{name: "Queso gouda",                category: "lacteos",   unit: "gramos",      net_cost: Decimal.new("0.18"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("300")},
  %{name: "Mezcla quesos artesanales",  category: "lacteos",   unit: "gramos",      net_cost: Decimal.new("0.25"), stock_quantity: Decimal.new("1500"),  min_stock: Decimal.new("200")},

  # ── Bebidas / bases frías ────────────────────────────────────────────────
  %{name: "Agua filtrada",              category: "bebidas",   unit: "mililitros",  net_cost: Decimal.new("0.01"), stock_quantity: Decimal.new("50000"), min_stock: Decimal.new("5000")},
  %{name: "Agua tónica",                category: "bebidas",   unit: "mililitros",  net_cost: Decimal.new("0.04"), stock_quantity: Decimal.new("10000"), min_stock: Decimal.new("1000")},
  %{name: "Hielo",                      category: "bebidas",   unit: "gramos",      net_cost: Decimal.new("0.01"), stock_quantity: Decimal.new("20000"), min_stock: Decimal.new("2000")},
  %{name: "Miel de abeja",              category: "bebidas",   unit: "mililitros",  net_cost: Decimal.new("0.12"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("200")},

  # ── Polvos y especias ────────────────────────────────────────────────────
  %{name: "Cacao artesanal en polvo",   category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.30"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("100")},
  %{name: "Polvo de matcha culinario",  category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.80"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Mezcla masala chai",         category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.50"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Té Earl Grey",              category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.40"), stock_quantity: Decimal.new("300"),   min_stock: Decimal.new("50")},
  %{name: "Mezcla tisana frutos rojos", category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.45"), stock_quantity: Decimal.new("300"),   min_stock: Decimal.new("50")},
  %{name: "Canela en raja",             category: "alimentos", unit: "piezas",      net_cost: Decimal.new("2.00"), stock_quantity: Decimal.new("200"),   min_stock: Decimal.new("30")},
  %{name: "Piloncillo",                 category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.04"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("200")},
  %{name: "Hierbas finas mezcla",       category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.20"), stock_quantity: Decimal.new("200"),   min_stock: Decimal.new("30")},

  # ── Frutas / vegetales ───────────────────────────────────────────────────
  %{name: "Cúrcuma fresca",             category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.10"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Jengibre fresco",            category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.08"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Flores de Jamaica secas",    category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.15"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Limón amarillo",             category: "alimentos", unit: "piezas",      net_cost: Decimal.new("3.00"), stock_quantity: Decimal.new("200"),   min_stock: Decimal.new("30")},
  %{name: "Frutos silvestres mix",      category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.25"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("200")},
  %{name: "Frutos rojos mix",           category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.22"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("200")},
  %{name: "Fruta de temporada",         category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.12"), stock_quantity: Decimal.new("3000"),  min_stock: Decimal.new("500")},
  %{name: "Tomate cherry",              category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.14"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("300")},
  %{name: "Champiñones",                category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.16"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("200")},
  %{name: "Chile morrón",               category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.10"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("150")},
  %{name: "Arúgula",                    category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.20"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("100")},
  %{name: "Cebolla morada",             category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.05"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("100")},
  %{name: "Cebolla caramelizada",       category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.10"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("100")},
  %{name: "Jalapeño",                   category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.06"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Frijoles negros cocidos",    category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.05"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("200")},
  %{name: "Cacahuate tostado",          category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.12"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("100")},
  %{name: "Extracto de vainilla",       category: "alimentos", unit: "mililitros",  net_cost: Decimal.new("0.50"), stock_quantity: Decimal.new("300"),   min_stock: Decimal.new("30")},

  # ── Proteínas / embutidos ────────────────────────────────────────────────
  %{name: "Pechuga de pavo",            category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.22"), stock_quantity: Decimal.new("1500"),  min_stock: Decimal.new("200")},
  %{name: "Arrachera",                  category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.50"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("150")},
  %{name: "Chistorra",                  category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.28"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("150")},
  %{name: "Pepperoni",                  category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.24"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("150")},
  %{name: "Pepinillos",                 category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.10"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Dip de aguacate",            category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.30"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("150")},
  %{name: "Salsa de tomate casera",     category: "alimentos", unit: "gramos",      net_cost: Decimal.new("0.08"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("300")},

  # ── Panadería / cereales ─────────────────────────────────────────────────
  %{name: "Pan campesino rebanado",     category: "panaderia", unit: "piezas",      net_cost: Decimal.new("6.00"), stock_quantity: Decimal.new("100"),   min_stock: Decimal.new("20")},
  %{name: "Pan para sandwich",          category: "panaderia", unit: "piezas",      net_cost: Decimal.new("4.00"), stock_quantity: Decimal.new("100"),   min_stock: Decimal.new("20")},
  %{name: "Granola",                    category: "panaderia", unit: "gramos",      net_cost: Decimal.new("0.18"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("100")},
  %{name: "Avena entera",               category: "panaderia", unit: "gramos",      net_cost: Decimal.new("0.05"), stock_quantity: Decimal.new("2000"),  min_stock: Decimal.new("200")},
  %{name: "Semillas mix",               category: "panaderia", unit: "gramos",      net_cost: Decimal.new("0.22"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")},
  %{name: "Crema de avellanas",         category: "panaderia", unit: "gramos",      net_cost: Decimal.new("0.35"), stock_quantity: Decimal.new("1000"),  min_stock: Decimal.new("100")},
  %{name: "Mermelada artesanal",        category: "panaderia", unit: "gramos",      net_cost: Decimal.new("0.20"), stock_quantity: Decimal.new("500"),   min_stock: Decimal.new("50")}
]

inserted_products =
  Enum.map(ingredient_defs, fn attrs ->
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing)
  end)

product_map = Map.new(inserted_products, fn p -> {p.name, p.id} end)

IO.puts("✓ Ingredientes creados: #{length(inserted_products)} insumos internos")

# ---------------------------------------------------------------------------
# Recetas — ingredientes con cantidades por platillo
# ---------------------------------------------------------------------------
recipes = [
  # ── Café Filtrados ────────────────────────────────────────────────────────
  {"Espresso",           "Granos de café blend",      14},
  {"Espresso",           "Agua filtrada",             30},

  {"Americano",          "Granos de café blend",      14},
  {"Americano",          "Agua filtrada",            200},

  {"Flat White",         "Granos de café blend",      18},
  {"Flat White",         "Leche entera",             150},

  {"Cappuccino",         "Granos de café blend",      14},
  {"Cappuccino",         "Leche entera",             120},
  {"Cappuccino",         "Agua filtrada",             30},

  {"Latte",              "Granos de café blend",      14},
  {"Latte",              "Leche entera",             200},
  {"Latte",              "Agua filtrada",             30},

  {"Café de Olla",       "Granos de café blend",      14},
  {"Café de Olla",       "Agua filtrada",            240},
  {"Café de Olla",       "Canela en raja",             1},
  {"Café de Olla",       "Piloncillo",                15},

  {"Matcha Culinario",   "Polvo de matcha culinario",  5},
  {"Matcha Culinario",   "Leche entera",             200},

  {"Chocolate",          "Cacao artesanal en polvo",  25},
  {"Chocolate",          "Leche entera",             200},

  {"Mocca",              "Granos de café blend",      14},
  {"Mocca",              "Cacao artesanal en polvo",  15},
  {"Mocca",              "Leche entera",             150},
  {"Mocca",              "Agua filtrada",             30},

  # ── Sin Cafeína ───────────────────────────────────────────────────────────
  {"Earl Grey",          "Té Earl Grey",               4},
  {"Earl Grey",          "Agua filtrada",            240},

  {"Cúrcuma y Jengibre", "Cúrcuma fresca",             5},
  {"Cúrcuma y Jengibre", "Jengibre fresco",            5},
  {"Cúrcuma y Jengibre", "Agua filtrada",            240},
  {"Cúrcuma y Jengibre", "Miel de abeja",             10},

  {"Masala Chai",        "Mezcla masala chai",        10},
  {"Masala Chai",        "Leche de avena",           200},

  {"Tisana Frutos Rojos","Mezcla tisana frutos rojos", 5},
  {"Tisana Frutos Rojos","Agua filtrada",            240},

  {"Grano Nacional — Atlixco de las Flores", "Granos de café blend", 15},
  {"Grano Nacional — Atlixco de las Flores", "Agua filtrada",       200},

  {"Cafecito Internacional", "Granos de café blend", 15},
  {"Cafecito Internacional", "Agua filtrada",        200},

  # ── Oleos y Mocktails ─────────────────────────────────────────────────────
  {"Cold Brew",          "Granos de café blend",      35},
  {"Cold Brew",          "Agua filtrada",            350},
  {"Cold Brew",          "Hielo",                    150},

  {"Limonada Clásica",   "Limón amarillo",             2},
  {"Limonada Clásica",   "Agua filtrada",            300},
  {"Limonada Clásica",   "Miel de abeja",             20},
  {"Limonada Clásica",   "Hielo",                    150},

  {"Limonada Frutos Silvestres", "Limón amarillo",    2},
  {"Limonada Frutos Silvestres", "Frutos silvestres mix", 50},
  {"Limonada Frutos Silvestres", "Agua filtrada",   250},
  {"Limonada Frutos Silvestres", "Hielo",           150},

  {"Limonada Rosa",      "Limón amarillo",             2},
  {"Limonada Rosa",      "Frutos rojos mix",          30},
  {"Limonada Rosa",      "Agua filtrada",            250},
  {"Limonada Rosa",      "Hielo",                    150},

  {"Espresso Tonic",     "Granos de café blend",      18},
  {"Espresso Tonic",     "Agua tónica",             200},
  {"Espresso Tonic",     "Hielo",                    100},

  {"Smoothie Frutal",    "Fruta de temporada",       200},
  {"Smoothie Frutal",    "Hielo",                    100},

  {"Citric Brew",        "Granos de café blend",      35},
  {"Citric Brew",        "Agua filtrada",            300},
  {"Citric Brew",        "Limón amarillo",             1},
  {"Citric Brew",        "Hielo",                    150},

  {"Jamaica Brew",       "Granos de café blend",      35},
  {"Jamaica Brew",       "Flores de Jamaica secas",   10},
  {"Jamaica Brew",       "Agua filtrada",            300},
  {"Jamaica Brew",       "Hielo",                    150},

  {"Torito",             "Cacahuate tostado",         40},
  {"Torito",             "Extracto de vainilla",       3},
  {"Torito",             "Leche entera",             200},

  # ── Extras ────────────────────────────────────────────────────────────────
  {"Leche Vegetal",      "Leche de avena",           200},
  {"Carga de Espresso",  "Granos de café blend",      14},
  {"Vaso de Leche",      "Leche entera",             200},

  # ── Sanduíses ─────────────────────────────────────────────────────────────
  {"Vegetariano",        "Pan para sandwich",          2},
  {"Vegetariano",        "Champiñones",               50},
  {"Vegetariano",        "Chile morrón",              30},
  {"Vegetariano",        "Queso gouda",               40},
  {"Vegetariano",        "Tomate cherry",             40},
  {"Vegetariano",        "Pepinillos",                20},

  {"Clásico",            "Pan para sandwich",          2},
  {"Clásico",            "Pechuga de pavo",           80},
  {"Clásico",            "Tomate cherry",             40},
  {"Clásico",            "Arúgula",                   20},

  {"Grilled Cheese",     "Pan para sandwich",          2},
  {"Grilled Cheese",     "Mezcla quesos artesanales", 60},
  {"Grilled Cheese",     "Salsa de tomate casera",    30},

  {"El Exótico",         "Pan para sandwich",          2},
  {"El Exótico",         "Chistorra",                 60},
  {"El Exótico",         "Queso gouda",               40},
  {"El Exótico",         "Cebolla caramelizada",      30},
  {"El Exótico",         "Tomate cherry",             30},
  {"El Exótico",         "Arúgula",                   15},
  {"El Exótico",         "Dip de aguacate",           30},

  {"El Favorito",        "Pan para sandwich",          2},
  {"El Favorito",        "Arrachera",                100},
  {"El Favorito",        "Queso gouda",               40},
  {"El Favorito",        "Dip de aguacate",           30},
  {"El Favorito",        "Tomate cherry",             30},
  {"El Favorito",        "Champiñones",               40},
  {"El Favorito",        "Chile morrón",              30},
  {"El Favorito",        "Arúgula",                   15},

  # ── Pan Pizza ─────────────────────────────────────────────────────────────
  {"Sencilla",           "Pan campesino rebanado",     2},
  {"Sencilla",           "Queso gouda",               40},
  {"Sencilla",           "Salsa de tomate casera",    40},
  {"Sencilla",           "Hierbas finas mezcla",       3},

  # Pan Pizza Vegetariano — distinto del Sandwich Vegetariano
  # (mismo nombre, distinta categoría — tomamos ambos por nombre exacto)
  # No hay colisión porque item_map toma el último insertado; en su lugar
  # usamos el slug de la categoría para distinguirlos si fuese necesario.
  # Por simplicidad asignamos los mismos ingredientes a ambos.
  {"Quesos",             "Pan campesino rebanado",     2},
  {"Quesos",             "Mezcla quesos artesanales", 70},
  {"Quesos",             "Salsa de tomate casera",    40},
  {"Quesos",             "Hierbas finas mezcla",       3},

  {"El Viejo y Confiable","Pan campesino rebanado",    2},
  {"El Viejo y Confiable","Pepperoni",                50},
  {"El Viejo y Confiable","Queso gouda",              40},
  {"El Viejo y Confiable","Salsa de tomate casera",   40},

  {"El Mexa",            "Pan campesino rebanado",     2},
  {"El Mexa",            "Salsa de tomate casera",    40},
  {"El Mexa",            "Frijoles negros cocidos",   40},
  {"El Mexa",            "Jalapeño",                  20},
  {"El Mexa",            "Chistorra",                 50},
  {"El Mexa",            "Queso gouda",               40},
  {"El Mexa",            "Cebolla morada",            20},
  {"El Mexa",            "Champiñones",               30},

  # ── Para Almorzar ─────────────────────────────────────────────────────────
  {"Pan Tostado Mexa",   "Pan campesino rebanado",     2},
  {"Pan Tostado Mexa",   "Miel de abeja",             20},
  {"Pan Tostado Mexa",   "Fruta de temporada",        80},
  {"Pan Tostado Mexa",   "Mermelada artesanal",       20},

  {"Fruta de Temporada", "Fruta de temporada",       200},
  {"Fruta de Temporada", "Queso gouda",               30},
  {"Fruta de Temporada", "Arúgula",                   10},
  {"Fruta de Temporada", "Yoghurt natural",           80},
  {"Fruta de Temporada", "Miel de abeja",             15},
  {"Fruta de Temporada", "Granola",                   30},

  {"Avena Trasnochada",  "Avena entera",              80},
  {"Avena Trasnochada",  "Leche entera",             200},
  {"Avena Trasnochada",  "Fruta de temporada",        80},
  {"Avena Trasnochada",  "Semillas mix",              15},

  {"Toast Francés",      "Pan campesino rebanado",     2},
  {"Toast Francés",      "Crema de avellanas",        40},
  {"Toast Francés",      "Fruta de temporada",        80},
  {"Toast Francés",      "Miel de abeja",             15}
]

# Also link Pan Pizza "Vegetariano" (same name as Sandwich "Vegetariano").
# We find all items named "Vegetariano" and add the pizza toppings for the
# second one (Pan Pizza category).
vegetariano_items =
  Enum.filter(inserted_items, &(&1.name == "Vegetariano"))

pizza_vegetariano_id =
  case vegetariano_items do
    [_, second | _] -> second.id
    _ -> nil
  end

if pizza_vegetariano_id do
  pizza_veg_ingredients = [
    {"Pan campesino rebanado", 2},
    {"Champiñones", 40},
    {"Chile morrón", 30},
    {"Queso gouda", 40},
    {"Tomate cherry", 30},
    {"Arúgula", 15}
  ]

  Enum.each(pizza_veg_ingredients, fn {product_name, qty} ->
    if pid = product_map[product_name] do
      %MenuItemIngredient{}
      |> MenuItemIngredient.changeset(%{
        menu_item_id: pizza_vegetariano_id,
        product_id: pid,
        quantity: Decimal.new("#{qty}")
      })
      |> Repo.insert!(on_conflict: :nothing)
    end
  end)
end

recipe_count =
  Enum.reduce(recipes, 0, fn {item_name, product_name, qty}, acc ->
    item_id = item_map[item_name]
    product_id = product_map[product_name]

    if item_id && product_id do
      %MenuItemIngredient{}
      |> MenuItemIngredient.changeset(%{
        menu_item_id: item_id,
        product_id: product_id,
        quantity: Decimal.new("#{qty}")
      })
      |> Repo.insert!(on_conflict: :nothing)

      acc + 1
    else
      acc
    end
  end)

IO.puts("✓ Recetas creadas: #{recipe_count} vínculos ingrediente-platillo")

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
    caption: "Tu lugar favorito en Santa María la Ribera",
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
