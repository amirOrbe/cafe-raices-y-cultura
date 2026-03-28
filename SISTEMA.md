# Café Raíces y Cultura — Documentación del Sistema

## Perfiles de usuario

| Perfil | Rol en BD | Estación | Acceso |
|---|---|---|---|
| **Administrador** | `admin` | — | Todo el panel `/admin/*` + vistas de empleado |
| **Mesero** | `empleado` | `sala` | `/mesa` y `/mesa/:id` |
| **Cocina** | `empleado` | `cocina` | `/cocina` |
| **Barra** | `empleado` | `barra` | `/barra` |
| **Público** | — | — | `/`, `/menu`, `/colaboraciones` |

---

## Qué puede ver y hacer cada perfil

### Mesero (`/mesa`, `/mesa/:id`)

**Tablero de comandas** (`/mesa`):
- Ver todas las comandas activas (abiertas, enviadas, listas)
- Crear nueva comanda con nombre del cliente
- Ver indicadores visuales por comanda:
  - 🟡 Naranja pulsante = algún ítem lleva >15 min en preparación
  - 🟢 Verde = todo listo para servir
  - 🔵 Azul = bebidas listas pero comida aún en cocina
  - Nombre del mesero que abrió cada comanda

**Comanda individual** (`/mesa/:id`):
- Agregar platillos y bebidas del menú
- Agregar extras de ingrediente a un platillo específico
- Ajustar cantidades (solo ítems pendientes)
- Enviar ítems a cocina y barra
- Ver estado de cada ítem en tiempo real:
  - Sin enviar / En preparación / ¡Listo! / Servido
- Marcar ítems como **servidos** (una vez que los entrega a la mesa)
- Cancelar ítems (con o sin restaurar inventario)
- Cobrar y cerrar la comanda (efectivo, tarjeta, transferencia)

---

### Cocina (`/cocina`)

- Ver únicamente los ítems de comida (categoría `food` / `extra`)
- Cada comanda muestra sus platillos pendientes con botón **"Listo"** por ítem
- Si un ítem es un extra de ingrediente, ve a qué platillo pertenece: `↳ para Sandwich Clásico`
- Botón **"Todo listo — {cliente}"** marca todos los platillos de la comanda como listos
- Sección **"Listos para servir"**: comandas donde todo el food está listo
- Contador de pedidos pendientes en tiempo real

---

### Barra (`/barra`)

- Ver únicamente ítems de bebida (categoría `drink`)
- Botón **"Listo"** por cada bebida
- Botón **"Todo listo — {cliente}"** marca todas las bebidas de la comanda
- Sección **"Listos para servir"**: comandas donde todas las bebidas están listas
- Contador de pedidos pendientes en tiempo real

---

### Administrador (`/admin/*`)

| Vista | URL | Qué muestra |
|---|---|---|
| **Dashboard** | `/admin` | KPIs de usuarios, inventario bajo stock, accesos rápidos |
| **Usuarios** | `/admin/usuarios` | CRUD de empleados y admins |
| **Menú** | `/admin/platillos` | CRUD de platillos, precios, ingredientes de receta |
| **Insumos** | `/admin/insumos` | Inventario: productos, stock, costo, proveedor |
| **Proveedores** | `/admin/proveedores` | CRUD de proveedores |
| **Eventos** | `/admin/eventos` | Gestión de eventos del café |
| **Colaboradores** | `/admin/colaboradores` | Personas o marcas aliadas |
| **Ventas** | `/admin/ventas` | Ingresos, ticket promedio, método de pago, historial de comandas cerradas |
| **Rendimiento** | `/admin/rendimiento` | Tiempo de preparación por empleado de cocina/barra, tiempo de servicio y recogida por mesero |

---

## Flujo completo de una comanda

A continuación un ejemplo real: **mesa con 2 personas piden 2 cafés y 1 sandwich**.

```
╔══════════════════════════════════════════════════════════════════════╗
║                        MESERO  (sala)                               ║
╚══════════════════════════════════════════════════════════════════════╝

  /mesa
  ┌─────────────────────────────────────────────┐
  │  [+ Nueva cuenta]                           │
  │  Nombre: "Mesa 4 — Juan"                    │
  │  [Crear]                                    │
  └─────────────────────────────────────────────┘

  → Orders.create_order(%{customer_name: "Mesa 4 — Juan", user_id: mesero.id})
  → order.status = "open"

  /mesa/:id
  ┌─────────────────────────────────────────────┐
  │  Comanda: Mesa 4 — Juan           [Abierta] │
  │                                             │
  │  [Menú]  Categoría: Café Filtrados          │
  │  ─────────────────────────────────────────  │
  │  Espresso $45         [Agregar] [⊕ Extras]  │
  │  Flat White $65       [Agregar] [⊕ Extras]  │
  │  ...                                        │
  │                                             │
  │  Categoría: Sanduíches                      │
  │  ─────────────────────────────────────────  │
  │  Clásico $115         [Agregar] [⊕ Extras]  │
  └─────────────────────────────────────────────┘

  Mesero agrega:
  → add_item(menu_item: Espresso)   → order_item.status = "pending"
  → add_item(menu_item: Flat White) → order_item.status = "pending"
  → add_item(menu_item: Clásico)    → order_item.status = "pending"

  ┌─────────────────────────────────────────────┐
  │  Comanda: Mesa 4 — Juan                     │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  Espresso           1×  [−][+]  [Sin enviar]│
  │  Flat White         1×  [−][+]  [Sin enviar]│
  │  Clásico            1×  [−][+]  [Sin enviar]│
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  Total: $225                                │
  │  [✈ Enviar a cocina y barra]                │
  └─────────────────────────────────────────────┘

  → send_to_kitchen(order)
     • Espresso  → status="sent", sent_at=now, deducta receta
     • Flat White → status="sent", sent_at=now, deduce receta
     • Clásico   → status="sent", sent_at=now, deduce receta
     • order.status = "sent"
     • PubSub broadcast → cocina y barra se actualizan
```

```
╔══════════════════════════════════════════════════════════════════════╗
║                     BARRA  (en paralelo)                            ║
╚══════════════════════════════════════════════════════════════════════╝

  /barra
  ┌───────────────────────────────────────────────────────────┐
  │  🍹 Barra                               [2 pedidos]       │
  │                                                           │
  │  ┌─────────────────────────────────────────────────────┐  │
  │  │  Mesa 4 — Juan                     [Enviado]        │  │
  │  │  2 bebidas                                          │  │
  │  │  ─────────────────────────────────────────────────  │  │
  │  │  1× Espresso                         [Listo]        │  │
  │  │  1× Flat White                       [Listo]        │  │
  │  │  ─────────────────────────────────────────────────  │  │
  │  │  [✓ Todo listo — Mesa 4 — Juan]                     │  │
  │  └─────────────────────────────────────────────────────┘  │
  └───────────────────────────────────────────────────────────┘

  Barista marca Espresso:
  → mark_item_ready(espresso.id, barista.id)
     • status="ready", ready_at=now, marked_ready_by_id=barista.id
     • PubSub broadcast

  Barista presiona "Todo listo — Mesa 4 — Juan":
  → mark_all_drinks_ready(order_id, barista.id)
     • Flat White → status="ready", ready_at=now
     • PubSub broadcast

  ┌──────────────────────────────────────────────┐
  │  LISTOS PARA SERVIR                          │
  │  ┌────────────────────────────────────────┐  │
  │  │  Mesa 4 — Juan            [Lista] ✓    │  │
  │  │  2 bebidas                             │  │
  │  └────────────────────────────────────────┘  │
  └──────────────────────────────────────────────┘
```

```
╔══════════════════════════════════════════════════════════════════════╗
║                     COCINA  (en paralelo)                           ║
╚══════════════════════════════════════════════════════════════════════╝

  /cocina
  ┌──────────────────────────────────────────────────────────┐
  │  🍳 Cocina                              [1 pedido]       │
  │                                                          │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │  Mesa 4 — Juan                    [Enviado]        │  │
  │  │  1 platillo                                        │  │
  │  │  ──────────────────────────────────────────────    │  │
  │  │  1× Clásico                        [Listo]         │  │
  │  │  ──────────────────────────────────────────────    │  │
  │  │  [✓ Todo listo — Mesa 4 — Juan]                    │  │
  │  └────────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────┘

  Cocinero presiona "Todo listo — Mesa 4 — Juan":
  → Clásico → status="ready", ready_at=now, marked_ready_by_id=cocinero.id
  → mark_order_ready(order)
     • order.status = "ready"
     • PubSub broadcast → mesero recibe alerta

  ┌──────────────────────────────────────────────┐
  │  LISTOS PARA SERVIR                          │
  │  ┌────────────────────────────────────────┐  │
  │  │  Mesa 4 — Juan            [Lista] ✓    │  │
  │  │  1 platillo                            │  │
  │  └────────────────────────────────────────┘  │
  └──────────────────────────────────────────────┘
```

```
╔══════════════════════════════════════════════════════════════════════╗
║                   MESERO — Sirve y cobra                            ║
╚══════════════════════════════════════════════════════════════════════╝

  La comanda del mesero se actualiza en tiempo real:

  ┌─────────────────────────────────────────────────────────┐
  │  Mesa 4 — Juan                              [Lista] ✓   │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  Espresso        [✓ Servir] 1× [−][+]  [¡Listo!]       │
  │  Flat White      [✓ Servir] 1× [−][+]  [¡Listo!]       │
  │  Clásico         [✓ Servir] 1× [−][+]  [¡Listo!]       │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  ✅ ¡Todo listo! Sirve la comanda.                      │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  Total: $225                                            │
  │  [✈ Enviar adicionales]  [💳 Cobrar y cerrar]          │
  └─────────────────────────────────────────────────────────┘

  Mesero recoge y sirve cada ítem:
  → mark_item_served(espresso.id, mesero.id)
     • status="served", served_at=now, served_by_id=mesero.id
  → mark_item_served(flat_white.id, mesero.id)
  → mark_item_served(clasico.id, mesero.id)

  La comanda queda limpia (ítems servidos en gris al fondo):

  ┌─────────────────────────────────────────────────────────┐
  │  Mesa 4 — Juan                              [Lista] ✓   │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  (sin ítems activos pendientes)                         │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  ░ Espresso   ░ 1×            ░ [Servido]   (gris)     │
  │  ░ Flat White ░ 1×            ░ [Servido]   (gris)     │
  │  ░ Clásico   ░ 1×            ░ [Servido]   (gris)     │
  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
  │  Total: $225                                            │
  │  [✈ Enviar adicionales]  [💳 Cobrar y cerrar]          │
  └─────────────────────────────────────────────────────────┘

  Mesero cobra:
  → show_payment_step → selecciona "Efectivo" → ingresa $300
  → Cambio: $75  ✓
  → confirm_close_order(order, %{payment_method: "efectivo", amount_paid: 300}, mesero.id)
     • Calcula total de ítems no cancelados
     • order.status = "closed"
     • order.closed_at = now
     • order.closed_by_id = mesero.id
     • PubSub broadcast → desaparece de tablero del mesero
     • PubSub broadcast → admin/ventas se actualiza en tiempo real
```

---

## Estados de una comanda: diagrama de transición

```
                    ┌──────────┐
                    │   OPEN   │  ← Recién creada
                    └────┬─────┘
                         │ send_to_kitchen()
                         ▼
                    ┌──────────┐
                    │   SENT   │  ← Ítems en preparación
                    └────┬─────┘
                         │ mark_order_ready()  (cocina)
                         ▼
                    ┌──────────┐
                    │  READY   │  ← Todo preparado, mesero sirve
                    └────┬─────┘
                         │ close_order()  (mesero)
                         ▼
                    ┌──────────┐
                    │  CLOSED  │  ← Cobrada y finalizada
                    └──────────┘
```

## Estados de un ítem: diagrama de transición

```
             ┌─────────┐
             │ PENDING │  ← Agregado, no enviado
             └────┬────┘
                  │ send_to_kitchen()        │ remove_item()
                  ▼                          ▼ (solo pending)
             ┌─────────┐               [eliminado]
             │  SENT   │  ← En preparación (cocina/barra)
             └────┬────┘
                  │ mark_item_ready()        │ cancel_item(:not_prepared)
                  ▼                          ▼
             ┌─────────┐               ┌────────────┐
             │  READY  │               │ CANCELLED  │  stock restaurado
             └────┬────┘               └────────────┘
                  │ mark_item_served()       │ cancel_item(:waste)
                  │                          ▼
                  ▼                    ┌──────────────────┐
             ┌─────────┐              │ CANCELLED_WASTE  │  sin restaurar
             │ SERVED  │              └──────────────────┘
             └─────────┘
```

---

## Modelo de datos clave

```
User ──────────────────────────────────────────────────────────┐
  :name, :email                                                 │
  :role       → admin | empleado | cliente                      │
  :station    → cocina | barra | sala  (si empleado)            │
  :is_active                                                    │
                                                                │
Order ──────────────────────────────────────────────────────────┤
  :customer_name                                                │
  :status     → open | sent | ready | closed                    │
  :payment_method → efectivo | tarjeta | transferencia          │
  :amount_paid, :total (Decimal)                                │
  :closed_at                                                    │
  :user_id        FK → User (mesero que abrió)                  │
  :closed_by_id   FK → User (mesero que cobró)                  │
       │ has_many                                               │
       ▼                                                        │
OrderItem ──────────────────────────────────────────────────────┤
  :quantity, :notes                                             │
  :status     → pending | sent | ready | served |              │
                cancelled | cancelled_waste                     │
  :sent_at, :ready_at, :served_at (timestamps)                  │
  :portion_quantity  (Decimal, para extras de ingrediente)      │
  :menu_item_id      FK → MenuItem  (platillo o bebida)         │
  :product_id        FK → Product   (extra de ingrediente)      │
  :for_menu_item_id  FK → MenuItem  (a qué platillo va el extra)│
  :marked_ready_by_id FK → User (cocinero/barista)              │
  :served_by_id       FK → User (mesero que lo sirvió)  ────────┘

MenuItem
  :name, :price (Decimal)
  :available, :featured
  :category_id FK → Category
       │ has_many
       ▼
MenuItemIngredient (receta)
  :menu_item_id FK → MenuItem
  :product_id   FK → Product
  :quantity     Decimal (cantidad a descontar del inventario)

Category
  :name, :slug, :kind → food | drink | extra

Product (inventario)
  :name, :stock_quantity, :min_stock  (Decimal)
  :unit → gramos | litros | piezas | ...
  :net_cost, :sale_price (Decimal)
  :supplier_id FK → Supplier
```

---

## Métricas disponibles en Rendimiento

| Métrica | Qué mide | Quién la genera |
|---|---|---|
| **Tiempo de preparación** | `ready_at − sent_at` por ítem | Cocina / Barra |
| **Tiempo de servicio** | `closed_at − order.inserted_at` por comanda | Mesero |
| **Tiempo de recogida** | `served_at − ready_at` por ítem | Mesero |

El dashboard de Rendimiento agrupa estas métricas por empleado (avg, min, max) y resalta en rojo cuando se supera el umbral (15 min para prep, 60 min para servicio).

---

## Flujo de inventario

```
  Mesero agrega ítem a comanda
        │
        │ (ítems en "pending", sin descontar)
        ▼
  Mesero presiona "Enviar a cocina"
        │
        ├── MenuItem → busca su receta (MenuItemIngredient)
        │             descuenta quantity × item.quantity de cada Product
        │
        └── Extra (product_id) → descuenta portion_quantity × item.quantity

  Si cancela ANTES de preparar:
        → restaura stock (cancel_item :not_prepared)

  Si cancela DESPUÉS de preparar:
        → NO restaura stock (cancel_item :waste)

  PubSub "menu_stock" → waiter recarga disponibilidad de menú
  PubSub "admin:products" → admin ve inventario actualizado
```

---

## URLs de referencia rápida

| URL | Perfil | Descripción |
|---|---|---|
| `http://localhost:4000` | Público | Landing page |
| `http://localhost:4000/menu` | Público | Menú completo |
| `http://localhost:4000/iniciar-sesion` | Todos | Login |
| `http://localhost:4000/mesa` | Mesero | Tablero de comandas |
| `http://localhost:4000/mesa/:id` | Mesero | Comanda individual |
| `http://localhost:4000/cocina` | Cocina | Display de cocina |
| `http://localhost:4000/barra` | Barra | Display de barra |
| `http://localhost:4000/admin` | Admin | Dashboard |
| `http://localhost:4000/admin/ventas` | Admin | Ventas e historial |
| `http://localhost:4000/admin/rendimiento` | Admin | Rendimiento de empleados |
| `http://localhost:4000/admin/insumos` | Admin | Inventario |
| `http://localhost:4000/admin/platillos` | Admin | Menú / recetas |
| `http://localhost:4000/admin/usuarios` | Admin | Gestión de empleados |
