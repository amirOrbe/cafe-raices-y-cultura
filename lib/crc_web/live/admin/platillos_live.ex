defmodule CRCWeb.Admin.PlatillosLive do
  @moduledoc "Menu item (platillos) management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.Catalog.MenuItem
  alias CRC.Cloudinary

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Platillos · Admin")
      |> assign(:items, Catalog.list_all_menu_items())
      |> assign(:categories, Catalog.list_all_categories())
      |> assign(:available_products, Catalog.list_ingredient_products())
      |> assign(:filter_category, "all")
      |> assign(:status_filter, :available)
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:ingredients_draft, [])
      |> assign(:selected_product_id, "")
      |> assign(:ingredient_quantity_input, "")
      |> assign(:remove_image, false)
      |> assign(:expanded_ids, MapSet.new())
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — filters
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("set_category_filter", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :filter_category, cat)}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    id = String.to_integer(id)

    expanded =
      if MapSet.member?(socket.assigns.expanded_ids, id),
        do: MapSet.delete(socket.assigns.expanded_ids, id),
        else: MapSet.put(socket.assigns.expanded_ids, id)

    {:noreply, assign(socket, :expanded_ids, expanded)}
  end

  # ---------------------------------------------------------------------------
  # Events — modal / CRUD
  # ---------------------------------------------------------------------------

  def handle_event("new_item", _params, socket) do
    changeset = Catalog.change_menu_item(%MenuItem{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:ingredients_draft, [])
     |> assign(:selected_product_id, "")
     |> assign(:ingredient_quantity_input, "")
     |> assign(:remove_image, false)}
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    item = Catalog.get_menu_item_with_ingredients!(String.to_integer(id))
    changeset = Catalog.change_menu_item(item)

    draft =
      Enum.map(item.menu_item_ingredients, fn mii ->
        %{
          product_id: mii.product_id,
          product_name: mii.product.name,
          quantity: mii.quantity,
          unit: mii.product.unit
        }
      end)

    {:noreply,
     socket
     |> assign(:modal, {:edit, item})
     |> assign(:form, to_form(changeset))
     |> assign(:ingredients_draft, draft)
     |> assign(:selected_product_id, "")
     |> assign(:ingredient_quantity_input, "")
     |> assign(:remove_image, false)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     assign(socket,
       modal: nil,
       form: nil,
       ingredients_draft: [],
       remove_image: false
     )}
  end

  # Triggered by phx-change on the form — needed so auto_upload fires immediately
  # when the user selects a file. No server-side work needed here.
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_item", %{"menu_item" => params}, socket) do
    # Track whether a photo was selected before consuming (entries are cleared after)
    had_photo = socket.assigns.uploads.photo.entries != []

    # Upload photo to Cloudinary if one was selected
    uploaded_url =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
        case Cloudinary.upload(path, folder: "menu", content_type: entry.client_type) do
          {:ok, url} ->
            {:ok, url}

          {:error, reason} ->
            require Logger
            Logger.error("Cloudinary upload failed: #{inspect(reason)}")
            {:ok, nil}
        end
      end)
      |> List.first()

    # Detect silent upload failure (file was selected but URL came back nil)
    upload_failed = had_photo && is_nil(uploaded_url)

    # Decide final image_url:
    #   - New upload takes priority
    #   - "Remove" flag clears it
    #   - Otherwise leave the existing value untouched (don't send the key)
    params =
      cond do
        uploaded_url -> Map.put(params, "image_url", uploaded_url)
        socket.assigns.remove_image -> Map.put(params, "image_url", nil)
        true -> params
      end

    result =
      case socket.assigns.modal do
        :new -> Catalog.create_menu_item(params)
        {:edit, item} -> Catalog.update_menu_item(item, params)
      end

    case result do
      {:ok, item} ->
        Catalog.set_menu_item_ingredients(item.id, socket.assigns.ingredients_draft)
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        socket =
          socket
          |> put_flash(:info, "Platillo #{label} correctamente.")
          |> assign(:items, Catalog.list_all_menu_items())
          |> assign(:modal, nil)
          |> assign(:form, nil)
          |> assign(:ingredients_draft, [])
          |> assign(:remove_image, false)

        socket =
          if upload_failed do
            put_flash(
              socket,
              :error,
              "La foto no pudo subirse a Cloudinary. El platillo se guardó sin imagen."
            )
          else
            socket
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Catalog.get_menu_item!(String.to_integer(id))

    case Catalog.delete_menu_item(item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Platillo eliminado correctamente.")
         |> assign(:items, Catalog.list_all_menu_items())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el platillo.")}
    end
  end

  def handle_event("toggle_available", %{"id" => id}, socket) do
    item = Catalog.get_menu_item!(String.to_integer(id))

    case Catalog.toggle_menu_item_available(item) do
      {:ok, _} ->
        action = if item.available, do: "ocultado del menú", else: "publicado en el menú"

        {:noreply,
         socket
         |> put_flash(:info, "Platillo #{action}.")
         |> assign(:items, Catalog.list_all_menu_items())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar la disponibilidad.")}
    end
  end

  def handle_event("remove_image", _params, socket) do
    {:noreply, assign(socket, :remove_image, true)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  # ---------------------------------------------------------------------------
  # Events — ingredient draft management
  # ---------------------------------------------------------------------------

  def handle_event("select_ingredient", %{"ingredient_product_id" => pid}, socket) do
    {:noreply, assign(socket, :selected_product_id, pid)}
  end

  def handle_event("set_ingredient_qty", %{"ingredient_quantity" => qty}, socket) do
    {:noreply, assign(socket, :ingredient_quantity_input, qty)}
  end

  def handle_event("add_ingredient", _params, socket) do
    %{
      available_products: products,
      selected_product_id: pid_str,
      ingredient_quantity_input: qty_str,
      ingredients_draft: draft
    } = socket.assigns

    with true <- pid_str != "" and pid_str != nil,
         {pid, _} <- Integer.parse(pid_str),
         product <- Enum.find(products, &(&1.id == pid)),
         true <- product != nil,
         false <- Enum.any?(draft, &(&1.product_id == pid)),
         {qty_float, _} <- Float.parse(qty_str <> ""),
         true <- qty_float > 0 do
      qty = Decimal.from_float(qty_float)

      entry = %{
        product_id: product.id,
        product_name: product.name,
        quantity: qty,
        unit: product.unit
      }

      {:noreply,
       socket
       |> assign(:ingredients_draft, draft ++ [entry])
       |> assign(:selected_product_id, "")
       |> assign(:ingredient_quantity_input, "")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_ingredient", %{"product_id" => pid_str}, socket) do
    pid = String.to_integer(pid_str)
    draft = Enum.reject(socket.assigns.ingredients_draft, &(&1.product_id == pid))
    {:noreply, assign(socket, :ingredients_draft, draft)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% by_status = filter_by_status(@items, @status_filter) %>
    <% visible = filter_by_category(by_status, @filter_category) %>
    <% available_count = Enum.count(@items, & &1.available) %>
    <% unavailable_count = Enum.count(@items, &(!&1.available)) %>

    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Platillos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)} platillos {if @status_filter == :available,
              do: "disponibles",
              else: "no disponibles"}
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_item">
          <.icon name="hero-plus" class="size-4" /> Nuevo platillo
        </button>
      </div>

      <%!-- Margin legend --%>
      <details class="group rounded-xl border border-base-300 bg-base-100 text-sm shadow-sm">
        <summary class="flex cursor-pointer items-center gap-2 px-4 py-3 font-medium text-base-content/60 list-none select-none">
          <.icon name="hero-information-circle" class="size-4 shrink-0 text-info" />
          <span class="flex-1 text-xs">¿Qué significa el % de margen?</span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 transition-transform group-open:rotate-180"
          />
        </summary>
        <div class="px-4 pb-4 text-xs text-base-content/60 space-y-1.5 leading-relaxed">
          <p>
            El margen es <strong>(precio de venta − costo de ingredientes) / precio de venta × 100</strong>. Solo se calcula si el platillo tiene todos sus ingredientes con costo registrado.
          </p>
          <div class="flex flex-wrap gap-3 mt-2">
            <span class="badge badge-success">≥ 60% — saludable</span>
            <span class="badge badge-warning">35–59% — revisar precio o receta</span>
            <span class="badge badge-error">&lt; 35% — margen crítico</span>
          </div>
        </div>
      </details>

      <%!-- Status filter tabs --%>
      <div class="flex gap-2">
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :available, do: "btn-primary", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="available"
        >
          <.icon name="hero-check-circle" class="size-3.5" /> Disponibles
          <span class="badge badge-xs">{available_count}</span>
        </button>
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :unavailable, do: "btn-error", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="unavailable"
        >
          <.icon name="hero-eye-slash" class="size-3.5" /> Ocultos
          <span class="badge badge-xs">{unavailable_count}</span>
        </button>
      </div>

      <%!-- Category filter tabs --%>
      <div class="flex gap-2 overflow-x-auto pb-1 scrollbar-hide">
        <.cat_tab value="all" current={@filter_category} label="Todos" />
        <%= for cat <- @categories do %>
          <.cat_tab value={to_string(cat.id)} current={@filter_category} label={cat.name} />
        <% end %>
      </div>

      <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
      <div class="md:hidden flex flex-col gap-2">
        <%= if visible == [] do %>
          <div class="text-center py-12 text-base-content/40 text-sm bg-base-100 rounded-2xl border border-base-300">
            {cond do
              @status_filter == :unavailable && @filter_category == "all" ->
                "No hay platillos ocultos."

              @filter_category != "all" ->
                "No hay platillos en esta categoría."

              true ->
                "No hay platillos registrados. Crea el primero."
            end}
          </div>
        <% end %>
        <%= for item <- visible do %>
          <% expanded = MapSet.member?(@expanded_ids, item.id) %>
          <div class={[
            "bg-base-100 rounded-2xl border shadow-sm overflow-hidden",
            if(expanded, do: "border-primary/30", else: "border-base-300")
          ]}>
            <div class="p-3 flex items-center gap-3">
              <%!-- Thumbnail --%>
              <%= if item.image_url do %>
                <img
                  src={item.image_url}
                  class="w-14 h-14 rounded-xl object-cover shrink-0 border border-base-300"
                  loading="lazy"
                />
              <% else %>
                <div class="w-14 h-14 rounded-xl bg-base-200 flex items-center justify-center shrink-0 border border-base-300">
                  <.icon name="hero-photo" class="size-6 text-base-content/25" />
                </div>
              <% end %>
              <%!-- Info --%>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-1.5 flex-wrap">
                  <p class="font-semibold text-sm text-base-content truncate">{item.name}</p>
                  <%= if item.featured do %>
                    <.icon name="hero-star-solid" class="size-3 text-warning shrink-0" />
                  <% end %>
                </div>
                <%= if item.description do %>
                  <p class="text-xs text-base-content/50 truncate mt-0.5">{item.description}</p>
                <% end %>
                <div class="flex items-center gap-2 mt-1.5 flex-wrap">
                  <span class="badge badge-xs badge-ghost">
                    {if item.category, do: item.category.name, else: "Sin categoría"}
                  </span>
                  <span class="text-xs font-semibold text-base-content">
                    ${format_price(item.price)}
                  </span>
                  <% cost = Catalog.item_cost(item) %>
                  <%= if cost do %>
                    <% margin = item_margin(item.price, cost) %>
                    <span
                      class={"badge badge-xs #{margin_badge_class(margin)}"}
                      title="Margen sobre precio de venta"
                    >
                      {margin}% margen
                    </span>
                  <% else %>
                    <span
                      class="badge badge-xs badge-ghost"
                      title="Agrega ingredientes con costo para ver el margen"
                    >
                      Sin costo
                    </span>
                  <% end %>
                  <%= if item.available do %>
                    <span class="badge badge-xs badge-success">Visible</span>
                  <% else %>
                    <span class="badge badge-xs badge-ghost">Oculto</span>
                  <% end %>
                  <%= if item.menu_item_ingredients == [] do %>
                    <span class="badge badge-xs badge-warning gap-0.5">
                      <.icon name="hero-exclamation-triangle" class="size-2.5" />
                      Sin receta
                    </span>
                  <% end %>
                </div>
              </div>
              <%!-- Actions --%>
              <div class="flex flex-col items-center gap-1 shrink-0">
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  phx-click="edit_item"
                  phx-value-id={item.id}
                  title="Editar"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  class={[
                    "btn btn-ghost btn-xs btn-circle",
                    if(item.available, do: "text-warning", else: "text-success")
                  ]}
                  phx-click="toggle_available"
                  phx-value-id={item.id}
                  title={if item.available, do: "Ocultar del menú", else: "Publicar en menú"}
                >
                  <.icon
                    name={if item.available, do: "hero-eye-slash", else: "hero-eye"}
                    class="size-4"
                  />
                </button>
                <button
                  class="btn btn-ghost btn-xs btn-circle text-error"
                  phx-click="delete_item"
                  phx-value-id={item.id}
                  title="Eliminar"
                  data-confirm={"¿Eliminar «#{item.name}»? Esta acción no se puede deshacer."}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
            <%!-- Expand toggle --%>
            <button
              class="w-full flex items-center justify-center gap-1 py-1.5 text-xs text-base-content/40 hover:text-primary border-t border-base-200 hover:bg-primary/5 transition-colors"
              phx-click="toggle_expand"
              phx-value-id={item.id}
            >
              <.icon
                name={if expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
                class="size-3"
              />
              {if expanded, do: "Ocultar desglose", else: "Ver desglose de costos"}
            </button>
            <%!-- Expanded breakdown --%>
            <%= if expanded do %>
              <div class="border-t border-base-200 bg-base-200/30">
                <.cost_breakdown item={item} />
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
      <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra table-fixed w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th class="w-[33%]">Platillo</th>
                <th class="w-[12%]">Categoría</th>
                <th class="w-[15%]">Precio / Costo</th>
                <th class="w-[9%]">Margen</th>
                <th class="w-[9%]">Destacado</th>
                <th class="w-[8%]">Estado</th>
                <th class="w-[14%] text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for item <- visible do %>
                <% expanded = MapSet.member?(@expanded_ids, item.id) %>
                <tr class={["hover:bg-base-200/50 transition-colors", if(expanded, do: "bg-primary/5", else: "")]}>
                  <td class="max-w-0">
                    <div class="flex items-center gap-3">
                      <%= if item.image_url do %>
                        <img
                          src={item.image_url}
                          class="w-10 h-10 rounded-lg object-cover shrink-0 border border-base-300"
                          loading="lazy"
                        />
                      <% else %>
                        <div class="w-10 h-10 rounded-lg bg-base-200 flex items-center justify-center shrink-0 border border-base-300">
                          <.icon name="hero-photo" class="size-5 text-base-content/25" />
                        </div>
                      <% end %>
                      <div class="min-w-0 flex-1">
                        <p class="font-medium text-sm text-base-content truncate">{item.name}</p>
                        <%= if item.description do %>
                          <p class="text-xs text-base-content/50 truncate">{item.description}</p>
                        <% end %>
                        <%= if item.menu_item_ingredients == [] do %>
                          <span class="badge badge-xs badge-warning gap-0.5 mt-0.5 inline-flex">
                            <.icon name="hero-exclamation-triangle" class="size-2.5" />
                            Sin receta
                          </span>
                        <% end %>
                      </div>
                      <button
                        class="btn btn-ghost btn-xs btn-circle shrink-0 text-base-content/30 hover:text-primary"
                        phx-click="toggle_expand"
                        phx-value-id={item.id}
                        title={if expanded, do: "Cerrar desglose", else: "Ver desglose de costos"}
                      >
                        <.icon
                          name={if expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
                          class="size-3.5"
                        />
                      </button>
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-sm badge-ghost">
                      {if item.category, do: item.category.name, else: "—"}
                    </span>
                  </td>
                  <% cost = Catalog.item_cost(item) %>
                  <td>
                    <p class="text-sm font-medium text-base-content">${format_price(item.price)}</p>
                    <%= if cost do %>
                      <p class="text-xs text-base-content/45 mt-0.5">costo ${format_price(cost)}</p>
                    <% end %>
                  </td>
                  <td>
                    <%= if cost do %>
                      <% margin = item_margin(item.price, cost) %>
                      <span class={"badge badge-sm #{margin_badge_class(margin)}"}>
                        {margin}%
                      </span>
                    <% else %>
                      <span class="text-base-content/30 text-sm">—</span>
                    <% end %>
                  </td>
                  <td>
                    <%= if item.featured do %>
                      <span class="badge badge-sm badge-warning gap-1">
                        <.icon name="hero-star-solid" class="size-3" /> Destacado
                      </span>
                    <% end %>
                  </td>
                  <td>
                    <%= if item.available do %>
                      <span class="badge badge-sm badge-success">Visible</span>
                    <% else %>
                      <span class="badge badge-sm badge-ghost">Oculto</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-xs btn-circle"
                        phx-click="edit_item"
                        phx-value-id={item.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={[
                          "btn btn-ghost btn-xs btn-circle",
                          if(item.available, do: "text-warning", else: "text-success")
                        ]}
                        phx-click="toggle_available"
                        phx-value-id={item.id}
                        title={if item.available, do: "Ocultar del menú", else: "Publicar en menú"}
                      >
                        <.icon
                          name={if item.available, do: "hero-eye-slash", else: "hero-eye"}
                          class="size-4"
                        />
                      </button>
                      <button
                        class="btn btn-ghost btn-xs btn-circle text-error"
                        phx-click="delete_item"
                        phx-value-id={item.id}
                        title="Eliminar"
                        data-confirm={"¿Eliminar «#{item.name}»? Esta acción no se puede deshacer."}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
                <%= if expanded do %>
                  <tr>
                    <td colspan="7" class="p-0 border-b border-base-200">
                      <div class="bg-base-200/30">
                        <.cost_breakdown item={item} />
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="7" class="text-center py-12 text-base-content/40 text-sm">
                    {cond do
                      @status_filter == :unavailable && @filter_category == "all" ->
                        "No hay platillos ocultos."

                      @filter_category != "all" ->
                        "No hay platillos en esta categoría."

                      true ->
                        "No hay platillos registrados. Crea el primero."
                    end}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal --%>
    <%= if @modal != nil do %>
      <.item_modal
        form={@form}
        modal={@modal}
        categories={@categories}
        ingredients_draft={@ingredients_draft}
        available_products={@available_products}
        selected_product_id={@selected_product_id}
        ingredient_quantity_input={@ingredient_quantity_input}
        uploads={@uploads}
        remove_image={@remove_image}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Item modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :categories, :list, required: true
  attr :ingredients_draft, :list, required: true
  attr :available_products, :list, required: true
  attr :selected_product_id, :string, required: true
  attr :ingredient_quantity_input, :string, required: true
  attr :uploads, :map, required: true
  attr :remove_image, :boolean, default: false

  defp item_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo platillo", else: "Editar platillo"
    current_img = item_image(assigns.modal)
    assigns = assigns |> assign(:title, title) |> assign(:current_img, current_img)

    ~H"""
    <div
      id="item-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-2xl overflow-y-auto max-h-[95vh] sm:max-h-[92vh]">
        <%!-- Modal header --%>
        <div class="px-4 sm:px-6 py-3 sm:py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100 z-10">
          <h2 class="text-base sm:text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-3 sm:px-6 py-4 sm:py-5 space-y-4">
          <%!-- Step flow --%>
          <div class="flex items-center gap-2 text-xs flex-wrap">
            <span class="flex items-center gap-1.5 font-semibold text-primary">
              <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-primary text-primary-content text-[10px] font-bold shrink-0">
                1
              </span>
              Información
            </span>
            <.icon name="hero-chevron-right" class="size-3 text-base-content/30 shrink-0" />
            <span class="flex items-center gap-1.5 text-base-content/40">
              <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-base-300 text-base-content/50 text-[10px] font-bold shrink-0">
                2
              </span>
              Precio y destino
            </span>
            <.icon name="hero-chevron-right" class="size-3 text-base-content/30 shrink-0" />
            <span class="flex items-center gap-1.5 text-base-content/40">
              <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-base-300 text-base-content/50 text-[10px] font-bold shrink-0">
                3
              </span>
              Ingredientes
            </span>
          </div>

          <.form
            id="item-form"
            for={@form}
            phx-submit="save_item"
            phx-change="validate_upload"
            class="space-y-4"
          >
            <%!-- ── ① Información básica ──────────────────────────────────────── --%>
            <div class="rounded-xl border border-base-300 bg-base-200/40 p-3 sm:p-4 space-y-3">
              <p class="text-xs font-semibold uppercase tracking-wider text-base-content/40 flex items-center gap-1.5">
                <span class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-primary text-primary-content text-[10px] font-bold">
                  1
                </span>
                Información básica
              </p>

              <.input
                field={@form[:name]}
                type="text"
                label="Nombre del platillo"
                placeholder="Ej. Cappuccino, Toast Francés, El Favorito"
              />

              <.input
                field={@form[:description]}
                type="textarea"
                label="Descripción (opcional)"
                placeholder="Breve texto que aparece bajo el nombre en el menú público..."
              />

              <%!-- Categoría — ancho completo para no mezclar alturas con checkbox --%>
              <.input
                field={@form[:category_id]}
                type="select"
                label="Categoría"
                options={[{"— Selecciona categoría —", ""} | Enum.map(@categories, &{&1.name, &1.id})]}
              />

              <%!-- Checkboxes como tarjetas iguales — misma altura, misma estructura --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label class="flex items-start gap-3 rounded-xl border border-base-300 bg-base-100 p-3 cursor-pointer hover:bg-base-200/60 transition-colors">
                  <div class="pt-0.5 shrink-0">
                    <input type="hidden" name="menu_item[featured]" value="false" />
                    <input
                      type="checkbox"
                      name="menu_item[featured]"
                      value="true"
                      class="checkbox checkbox-primary checkbox-sm"
                      checked={@form[:featured].value != false && @form[:featured].value != "false"}
                    />
                  </div>
                  <div>
                    <p class="text-sm font-medium text-base-content">Platillo destacado ⭐</p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      Aparece primero con una estrella en el menú.
                    </p>
                  </div>
                </label>
                <label class="flex items-start gap-3 rounded-xl border border-base-300 bg-base-100 p-3 cursor-pointer hover:bg-base-200/60 transition-colors">
                  <div class="pt-0.5 shrink-0">
                    <input type="hidden" name="menu_item[available]" value="false" />
                    <input
                      type="checkbox"
                      name="menu_item[available]"
                      value="true"
                      class="checkbox checkbox-primary checkbox-sm"
                      checked={@form[:available].value != false && @form[:available].value != "false"}
                    />
                  </div>
                  <div>
                    <p class="text-sm font-medium text-base-content">Visible en el menú</p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      Los meseros pueden pedirlo en comandas.
                    </p>
                  </div>
                </label>
              </div>
            </div>

            <%!-- ── ② Precio y destino ─────────────────────────────────────────── --%>
            <div class="rounded-xl border border-base-300 bg-base-200/40 p-3 sm:p-4 space-y-3">
              <p class="text-xs font-semibold uppercase tracking-wider text-base-content/40 flex items-center gap-1.5">
                <span class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-base-300 text-base-content/50 text-[10px] font-bold">
                  2
                </span>
                Precio y destino
              </p>

              <%!-- Precio — ancho completo --%>
              <div>
                <.input
                  field={@form[:price]}
                  type="number"
                  label="Precio de venta ($)"
                  placeholder="0.00"
                  step="0.01"
                  min="0.01"
                />
                <p class="text-xs text-base-content/40 mt-1">
                  Lo que el cliente paga. Aparece en el menú y en las comandas.
                </p>
              </div>

              <%!-- Destination cards (radio styled as visual cards via peer-checked) --%>
              <div>
                <label class="label pb-1.5">
                  <span class="label-text font-medium">¿Dónde se prepara?</span>
                </label>
                <div class="grid grid-cols-2 gap-2 sm:gap-3">
                  <label class="cursor-pointer">
                    <input
                      type="radio"
                      name="menu_item[destination]"
                      value="cocina"
                      class="sr-only peer"
                      checked={@form[:destination].value not in ["barra"]}
                    />
                    <div class="flex flex-col items-center gap-1.5 sm:gap-2 p-2 sm:p-4 rounded-xl border-2 border-base-300 peer-checked:border-primary peer-checked:bg-primary/5 hover:border-primary/30 transition-all">
                      <span class="text-xl sm:text-3xl">🍳</span>
                      <div class="text-center">
                        <p class="font-semibold text-xs sm:text-sm text-base-content">Cocina</p>
                        <p class="hidden sm:block text-xs text-base-content/50 mt-0.5">
                          Platillos, sandwiches, ensaladas…
                        </p>
                      </div>
                    </div>
                  </label>
                  <label class="cursor-pointer">
                    <input
                      type="radio"
                      name="menu_item[destination]"
                      value="barra"
                      class="sr-only peer"
                      checked={@form[:destination].value == "barra"}
                    />
                    <div class="flex flex-col items-center gap-1.5 sm:gap-2 p-2 sm:p-4 rounded-xl border-2 border-base-300 peer-checked:border-info peer-checked:bg-info/5 hover:border-info/30 transition-all">
                      <span class="text-xl sm:text-3xl">☕</span>
                      <div class="text-center">
                        <p class="font-semibold text-xs sm:text-sm text-base-content">Barra</p>
                        <p class="hidden sm:block text-xs text-base-content/50 mt-0.5">
                          Bebidas, cafés, cócteles…
                        </p>
                      </div>
                    </div>
                  </label>
                </div>
              </div>
            </div>

            <%!-- ── Foto del platillo ───────────────────────────────────────────── --%>
            <div>
              <p class="text-sm font-medium text-base-content mb-2">
                Foto del platillo <span class="text-base-content/40 font-normal">(opcional)</span>
              </p>

              <%!-- Show current image when editing (unless user hit "remove") --%>
              <%= if @current_img && !@remove_image do %>
                <div class="flex items-start gap-3 p-3 bg-base-200 rounded-xl mb-2">
                  <img
                    src={@current_img}
                    class="w-20 h-20 rounded-lg object-cover shrink-0 border border-base-300"
                  />
                  <div class="flex-1 min-w-0 space-y-1">
                    <p class="text-sm font-medium text-base-content">Foto actual</p>
                    <p class="text-xs text-base-content/50 break-all">{@current_img}</p>
                    <button
                      type="button"
                      class="btn btn-xs btn-error btn-outline gap-1 mt-1"
                      phx-click="remove_image"
                    >
                      <.icon name="hero-trash" class="size-3" /> Eliminar foto
                    </button>
                  </div>
                </div>
              <% end %>

              <%!-- Upload area (shown when no current image, or after remove) --%>
              <%= if !@current_img || @remove_image do %>
                <label
                  for={@uploads.photo.ref}
                  class="flex flex-col items-center justify-center gap-2 w-full py-6 px-4 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 hover:bg-primary/5 cursor-pointer transition-all duration-200"
                >
                  <div class="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10">
                    <.icon name="hero-photo" class="size-5 text-primary" />
                  </div>
                  <div class="text-center">
                    <p class="text-sm font-medium text-base-content">
                      Selecciona una foto del platillo
                    </p>
                    <p class="text-xs text-base-content/40 mt-0.5">JPG, PNG o WebP · Máx. 5 MB</p>
                  </div>
                  <.live_file_input upload={@uploads.photo} class="sr-only" />
                </label>
              <% end %>

              <%!-- Preview of selected (not yet saved) file --%>
              <%= for entry <- @uploads.photo.entries do %>
                <div class="flex items-center gap-3 mt-2 p-2.5 bg-base-200 rounded-xl">
                  <.live_img_preview entry={entry} class="w-12 h-12 object-cover rounded-lg shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">{entry.client_name}</p>
                    <div class="w-full bg-base-300 rounded-full h-1.5 mt-1.5">
                      <div
                        class="bg-primary h-1.5 rounded-full transition-all duration-300"
                        style={"width: #{entry.progress}%"}
                      />
                    </div>
                  </div>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs btn-circle text-error shrink-0"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                  >
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                </div>
                <%= for err <- upload_errors(@uploads.photo, entry) do %>
                  <p class="text-xs text-error mt-1">{upload_error_to_string(err)}</p>
                <% end %>
              <% end %>
            </div>

            <%!-- ── ③ Ingredientes (receta) ────────────────────────────────────── --%>
            <div class="rounded-xl border border-base-300 bg-base-200/40 p-3 sm:p-4 space-y-3">
              <div class="flex items-center gap-1.5">
                <span class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-base-300 text-base-content/50 text-[10px] font-bold shrink-0">
                  3
                </span>
                <p class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
                  Ingredientes de la receta
                </p>
                <span class="badge badge-xs badge-ghost">{length(@ingredients_draft)}</span>
              </div>
              <p class="text-xs text-base-content/40 leading-relaxed">
                Define qué insumos usa este platillo y en qué cantidad <strong>por porción</strong>.
                El sistema descuenta ese stock automáticamente cada vez que se envía a cocina o barra,
                y calcula el costo de producción y el margen de ganancia que ves en la lista.
              </p>

              <%!-- Current ingredient list --%>
              <%= if @ingredients_draft != [] do %>
                <div class="space-y-1.5">
                  <%= for ing <- @ingredients_draft do %>
                    <div class="flex items-center justify-between py-1.5 px-3 bg-base-100 border border-base-300 rounded-lg">
                      <span class="text-sm font-medium text-base-content">{ing.product_name}</span>
                      <div class="flex items-center gap-3">
                        <span class="text-xs font-mono text-base-content/60">
                          {format_qty(ing.quantity)} {unit_abbr(ing.unit)}
                        </span>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs text-error p-0"
                          phx-click="remove_ingredient"
                          phx-value-product_id={ing.product_id}
                          title="Quitar ingrediente"
                        >
                          <.icon name="hero-x-mark" class="size-3.5" />
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Add ingredient picker — resolves selected product's unit dynamically --%>
              <% selected_product = Enum.find(@available_products, &(to_string(&1.id) == @selected_product_id)) %>
              <% selected_unit = if selected_product, do: unit_abbr(selected_product.unit), else: nil %>

              <div class="space-y-2">
                <%!-- Insumo select — full width always --%>
                <div>
                  <label class="label text-xs pb-0.5">Insumo</label>
                  <select
                    class="select select-sm w-full"
                    phx-change="select_ingredient"
                    name="ingredient_product_id"
                  >
                    <option value="">— Selecciona insumo —</option>
                    <%= for p <- @available_products do %>
                      <option value={p.id} selected={to_string(p.id) == @selected_product_id}>
                        {p.name} ({unit_abbr(p.unit)})
                      </option>
                    <% end %>
                  </select>
                </div>

                <%!-- Cantidad + Agregar — same row, qty is flex-1 --%>
                <div class="flex gap-2 items-end">
                  <div class="flex-1 min-w-0">
                    <label class="label text-xs pb-0.5">
                      Cantidad
                      <%= if selected_unit do %>
                        <span class="badge badge-xs badge-primary badge-outline ml-1">
                          {selected_unit}
                        </span>
                      <% end %>
                    </label>
                    <input
                      type="number"
                      class="input input-sm w-full"
                      placeholder={if selected_unit, do: "0.000 #{selected_unit}", else: "0.000"}
                      step="0.001"
                      min="0"
                      value={@ingredient_quantity_input}
                      phx-change="set_ingredient_qty"
                      name="ingredient_quantity"
                    />
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline btn-primary shrink-0"
                    phx-click="add_ingredient"
                  >
                    <.icon name="hero-plus" class="size-3.5" /> Agregar
                  </button>
                </div>
              </div>

              <%= if @available_products == [] do %>
                <p class="text-xs text-base-content/50">
                  No hay insumos disponibles. Crea insumos en
                  <a href="/admin/insumos" class="link link-primary">Inventario → Insumos</a>.
                </p>
              <% end %>
            </div>
            <%!-- ── End Ingredientes ───────────────────────────────────────────── --%>

            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear platillo", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Cost breakdown panel (shared by desktop sub-row and mobile accordion)
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true

  defp cost_breakdown(assigns) do
    cost = Catalog.item_cost(assigns.item)
    assigns = assign(assigns, :cost, cost)

    ~H"""
    <div class="px-4 py-3 space-y-2.5">
      <p class="text-[10px] font-bold uppercase tracking-wider text-base-content/30">
        Desglose de costos
      </p>

      <%= if @item.menu_item_ingredients == [] do %>
        <div class="flex items-center gap-2 text-xs text-warning py-1">
          <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" />
          <span>Sin ingredientes registrados — el costo y margen no pueden calcularse.</span>
          <button
            class="link link-warning ml-auto text-[10px] shrink-0"
            phx-click="edit_item"
            phx-value-id={@item.id}
          >
            Agregar receta →
          </button>
        </div>
      <% else %>
        <table class="w-full text-xs border-collapse">
          <thead>
            <tr class="text-base-content/30 text-[10px] uppercase border-b border-base-200">
              <th class="text-left py-1 pr-2 font-semibold">Ingrediente</th>
              <th class="text-right py-1 px-2 font-semibold">Cantidad</th>
              <th class="text-right py-1 px-2 font-semibold">Costo/u</th>
              <th class="text-right py-1 pl-2 font-semibold">Total</th>
            </tr>
          </thead>
          <tbody>
            <%= for mii <- @item.menu_item_ingredients do %>
              <tr class="border-b border-base-100/50">
                <td class="py-1 pr-2 text-base-content/70 font-medium">
                  {mii.product && mii.product.name}
                </td>
                <td class="py-1 px-2 text-right font-mono text-base-content/60">
                  {format_qty(mii.quantity)} {mii.product && unit_abbr(mii.product.unit)}
                </td>
                <td class="py-1 px-2 text-right font-mono">
                  <%= if mii.product && mii.product.net_cost do %>
                    <span class="text-base-content/60">${format_money(mii.product.net_cost)}</span>
                  <% else %>
                    <span class="text-warning text-[10px] font-medium">Sin costo</span>
                  <% end %>
                </td>
                <td class="py-1 pl-2 text-right font-mono font-semibold">
                  <%= if mii.product && mii.product.net_cost do %>
                    <span class="text-error">${format_money(ingredient_line_cost(mii))}</span>
                  <% else %>
                    <span class="text-base-content/30">—</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%!-- Summary bar --%>
        <% price_d = Decimal.new("#{@item.price}") %>
        <div class="flex items-center gap-x-4 gap-y-1 flex-wrap pt-1.5 text-xs border-t border-base-200">
          <span class="text-base-content/50">
            Costo:
            <strong class="text-error font-mono">
              {if @cost, do: "$#{format_money(@cost)}", else: "—"}
            </strong>
          </span>
          <span class="text-base-content/50">
            Venta:
            <strong class="font-mono text-base-content">${format_price(@item.price)}</strong>
          </span>
          <%= if @cost do %>
            <% profit = Decimal.sub(price_d, @cost) %>
            <% margin = item_margin(@item.price, @cost) %>
            <span class="text-base-content/50">
              Ganancia:
              <strong class={"font-mono #{if margin >= 60, do: "text-success", else: if(margin >= 35, do: "text-warning", else: "text-error")}"}>
                ${format_money(profit)}
              </strong>
              <span class={"badge badge-xs #{margin_badge_class(margin)} ml-0.5"}>{margin}%</span>
            </span>
          <% end %>
          <%= if Enum.any?(@item.menu_item_ingredients, fn mii ->
                !(mii.product && mii.product.net_cost)
              end) do %>
            <span class="badge badge-warning badge-xs gap-0.5 ml-auto">
              <.icon name="hero-exclamation-triangle" class="size-2.5" />
              Ingredientes sin costo
            </span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Category filter tab
  # ---------------------------------------------------------------------------

  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true

  defp cat_tab(assigns) do
    ~H"""
    <button
      class={[
        "btn btn-sm whitespace-nowrap",
        if(@value == @current, do: "btn-primary", else: "btn-ghost")
      ]}
      phx-click="set_category_filter"
      phx-value-category={@value}
    >
      {@label}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp filter_by_status(items, :available), do: Enum.filter(items, & &1.available)
  defp filter_by_status(items, :unavailable), do: Enum.filter(items, &(!&1.available))

  defp filter_by_category(items, "all"), do: items

  defp filter_by_category(items, cat_id) do
    {id, _} = Integer.parse(cat_id)
    Enum.filter(items, &(&1.category_id == id))
  end

  # Returns the existing image_url for the item being edited, or nil for new items.
  defp item_image(:new), do: nil
  defp item_image({:edit, item}), do: item.image_url

  defp upload_error_to_string(:too_large), do: "El archivo es demasiado grande (máx. 5 MB)."
  defp upload_error_to_string(:not_accepted), do: "Formato no aceptado. Usa JPG, PNG o WebP."
  defp upload_error_to_string(:too_many_files), do: "Solo se puede subir una foto a la vez."
  defp upload_error_to_string(_), do: "Error al subir el archivo."

  defp format_price(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_price(val), do: to_string(val)

  defp format_qty(nil), do: "0"

  defp format_qty(%Decimal{} = d) do
    if Decimal.integer?(d),
      do: d |> Decimal.to_integer() |> to_string(),
      else: Decimal.to_string(d)
  end

  defp format_qty(val), do: to_string(val)

  defp unit_abbr("piezas"), do: "pza"
  defp unit_abbr("gramos"), do: "gr"
  defp unit_abbr("kilogramos"), do: "kg"
  defp unit_abbr("mililitros"), do: "ml"
  defp unit_abbr("litros"), do: "lt"
  defp unit_abbr("onzas"), do: "oz"
  defp unit_abbr("paquetes"), do: "paq"
  defp unit_abbr(other), do: other

  # Margin as an integer percentage: (price - cost) / price * 100
  defp item_margin(price, cost) do
    price_d = Decimal.new(to_string(price))

    if Decimal.compare(price_d, Decimal.new(0)) == :gt do
      price_d
      |> Decimal.sub(cost)
      |> Decimal.div(price_d)
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(0)
      |> Decimal.to_integer()
    else
      0
    end
  end

  # Badge colour based on margin health
  defp margin_badge_class(m) when m >= 60, do: "badge-success"
  defp margin_badge_class(m) when m >= 35, do: "badge-warning"
  defp margin_badge_class(_), do: "badge-error"

  # Line cost for one ingredient row: quantity × net_cost per unit
  defp ingredient_line_cost(mii) do
    net_cost = (mii.product && mii.product.net_cost) || Decimal.new(0)
    Decimal.mult(mii.quantity, net_cost)
  end

  # Monetary display rounded to 2 decimal places, trailing zeros stripped
  defp format_money(%Decimal{} = d) do
    if Decimal.integer?(d),
      do: d |> Decimal.to_integer() |> to_string(),
      else:
        d
        |> Decimal.round(2)
        |> Decimal.to_string()
        |> String.trim_trailing("0")
        |> String.trim_trailing(".")
  end

  defp format_money(val), do: to_string(val)
end
