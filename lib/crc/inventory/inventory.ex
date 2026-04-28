defmodule CRC.Inventory do
  @moduledoc """
  Bounded context for inventory management.

  Handles suppliers (proveedores) and products/supplies (insumos).
  Products track stock levels and alert when below minimum threshold.
  """

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Inventory.Product
  alias CRC.Inventory.ProductCategory
  alias CRC.Inventory.ProductVariant
  alias CRC.Inventory.StockAdjustment
  alias CRC.Inventory.Supplier

  # ---------------------------------------------------------------------------
  # Suppliers
  # ---------------------------------------------------------------------------

  @doc "Returns all suppliers ordered by name."
  @spec list_suppliers() :: [Supplier.t()]
  def list_suppliers do
    Repo.all(from s in Supplier, order_by: [asc: s.name])
  end

  @doc "Returns active suppliers only, ordered by name."
  @spec list_active_suppliers() :: [Supplier.t()]
  def list_active_suppliers do
    Repo.all(from s in Supplier, where: s.active == true, order_by: [asc: s.name])
  end

  @doc "Gets a supplier by id. Raises if not found."
  @spec get_supplier!(integer()) :: Supplier.t()
  def get_supplier!(id), do: Repo.get!(Supplier, id)

  @doc "Creates a supplier."
  @spec create_supplier(map()) :: {:ok, Supplier.t()} | {:error, Ecto.Changeset.t()}
  def create_supplier(attrs) do
    %Supplier{}
    |> Supplier.changeset(attrs)
    |> Repo.insert()
    |> broadcast_supplier_change()
  end

  @doc "Updates a supplier."
  @spec update_supplier(Supplier.t(), map()) :: {:ok, Supplier.t()} | {:error, Ecto.Changeset.t()}
  def update_supplier(%Supplier{} = supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
    |> broadcast_supplier_change()
  end

  @doc "Toggles the active status of a supplier."
  @spec toggle_supplier_active(Supplier.t()) :: {:ok, Supplier.t()} | {:error, Ecto.Changeset.t()}
  def toggle_supplier_active(%Supplier{} = supplier) do
    supplier
    |> Supplier.changeset(%{active: !supplier.active})
    |> Repo.update()
    |> broadcast_supplier_change()
  end

  @doc "Returns an empty changeset for a new supplier."
  @spec change_supplier(Supplier.t(), map()) :: Ecto.Changeset.t()
  def change_supplier(%Supplier{} = supplier, attrs \\ %{}) do
    Supplier.changeset(supplier, attrs)
  end

  # ---------------------------------------------------------------------------
  # Products (Insumos)
  # ---------------------------------------------------------------------------

  @doc "Returns all products with supplier, category, and variants preloaded, ordered by name."
  @spec list_products() :: [Product.t()]
  def list_products do
    Repo.all(
      from p in Product,
        left_join: s in assoc(p, :supplier),
        left_join: c in assoc(p, :product_category),
        preload: [supplier: s, product_category: c],
        order_by: [asc: c.name, asc: p.name]
    )
    |> Repo.preload(:variants)
  end

  @doc "Returns products (without variants) with stock at or below minimum threshold."
  @spec list_low_stock_products() :: [Product.t()]
  def list_low_stock_products do
    Repo.all(
      from p in Product,
        where: p.active == true and p.stock_quantity <= p.min_stock,
        left_join: s in assoc(p, :supplier),
        preload: [supplier: s],
        order_by: [asc: p.name]
    )
  end

  @doc "Returns active variants with stock at or below their minimum threshold."
  @spec list_low_stock_variants() :: [ProductVariant.t()]
  def list_low_stock_variants do
    Repo.all(
      from v in ProductVariant,
        where: v.active == true and v.stock_quantity <= v.min_stock,
        join: p in assoc(v, :product),
        where: p.active == true,
        preload: [product: p],
        order_by: [asc: p.name, asc: v.name]
    )
  end

  @doc "Finds an active product by exact name (case-insensitive). Returns nil if not found."
  def find_product_by_name(name) do
    Product
    |> where([p], fragment("lower(?)", p.name) == ^String.downcase(name))
    |> Repo.one()
  end

  @doc "Gets a product by id with supplier, category, and variants preloaded. Raises if not found."
  @spec get_product!(integer()) :: Product.t()
  def get_product!(id) do
    Product
    |> Repo.get!(id)
    |> Repo.preload([:supplier, :product_category, :variants])
  end

  @doc "Creates a product."
  @spec create_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
    |> broadcast_product_change()
  end

  @doc "Updates a product."
  @spec update_product(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
    |> broadcast_product_change()
  end

  @doc "Toggles the active status of a product."
  @spec toggle_product_active(Product.t()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def toggle_product_active(%Product{} = product) do
    product
    |> Product.changeset(%{active: !product.active})
    |> Repo.update()
    |> broadcast_product_change()
  end

  @doc "Returns an empty changeset for a new product."
  @spec change_product(Product.t(), map()) :: Ecto.Changeset.t()
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  # ---------------------------------------------------------------------------
  # Product Variants (Tipos de insumo)
  # ---------------------------------------------------------------------------

  @doc "Returns all variants for a product, ordered by name."
  @spec list_variants_for_product(integer()) :: [ProductVariant.t()]
  def list_variants_for_product(product_id) do
    Repo.all(
      from v in ProductVariant,
        where: v.product_id == ^product_id,
        order_by: [asc: v.name]
    )
  end

  @doc "Gets a single variant by id. Raises if not found."
  @spec get_variant!(integer()) :: ProductVariant.t()
  def get_variant!(id), do: Repo.get!(ProductVariant, id)

  @doc "Creates a variant for the given product."
  @spec create_variant(integer(), map()) ::
          {:ok, ProductVariant.t()} | {:error, Ecto.Changeset.t()}
  def create_variant(product_id, attrs) do
    %ProductVariant{}
    |> ProductVariant.changeset(Map.put(attrs, "product_id", product_id))
    |> Repo.insert()
    |> broadcast_product_change_for_product(product_id)
  end

  @doc "Updates an existing variant."
  @spec update_variant(ProductVariant.t(), map()) ::
          {:ok, ProductVariant.t()} | {:error, Ecto.Changeset.t()}
  def update_variant(%ProductVariant{} = variant, attrs) do
    variant
    |> ProductVariant.changeset(attrs)
    |> Repo.update()
    |> broadcast_product_change_for_product(variant.product_id)
  end

  @doc "Deletes a variant."
  @spec delete_variant(ProductVariant.t()) ::
          {:ok, ProductVariant.t()} | {:error, Ecto.Changeset.t()}
  def delete_variant(%ProductVariant{} = variant) do
    product_id = variant.product_id

    variant
    |> Repo.delete()
    |> broadcast_product_change_for_product(product_id)
  end

  @doc "Toggles the active status of a variant."
  @spec toggle_variant_active(ProductVariant.t()) ::
          {:ok, ProductVariant.t()} | {:error, Ecto.Changeset.t()}
  def toggle_variant_active(%ProductVariant{} = variant) do
    variant
    |> ProductVariant.changeset(%{active: !variant.active})
    |> Repo.update()
    |> broadcast_product_change_for_product(variant.product_id)
  end

  @doc "Returns a changeset for a variant."
  @spec change_variant(ProductVariant.t(), map()) :: Ecto.Changeset.t()
  def change_variant(%ProductVariant{} = variant, attrs \\ %{}) do
    ProductVariant.changeset(variant, attrs)
  end

  # ---------------------------------------------------------------------------
  # Product Categories
  # ---------------------------------------------------------------------------

  @doc "Returns all product categories ordered by name."
  @spec list_product_categories() :: [ProductCategory.t()]
  def list_product_categories do
    Repo.all(from c in ProductCategory, order_by: [asc: c.name])
  end

  @doc "Returns product categories with product count."
  @spec list_product_categories_with_count() :: [map()]
  def list_product_categories_with_count do
    Repo.all(
      from c in ProductCategory,
        left_join: p in assoc(c, :products),
        group_by: c.id,
        select: %{id: c.id, name: c.name, inserted_at: c.inserted_at, product_count: count(p.id)},
        order_by: [asc: c.name]
    )
  end

  @doc "Gets a product category by id. Raises if not found."
  @spec get_product_category!(integer()) :: ProductCategory.t()
  def get_product_category!(id), do: Repo.get!(ProductCategory, id)

  @doc "Creates a product category."
  @spec create_product_category(map()) :: {:ok, ProductCategory.t()} | {:error, Ecto.Changeset.t()}
  def create_product_category(attrs) do
    %ProductCategory{}
    |> ProductCategory.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a product category."
  @spec update_product_category(ProductCategory.t(), map()) :: {:ok, ProductCategory.t()} | {:error, Ecto.Changeset.t()}
  def update_product_category(%ProductCategory{} = category, attrs) do
    category
    |> ProductCategory.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a product category."
  @spec delete_product_category(ProductCategory.t()) :: {:ok, ProductCategory.t()} | {:error, Ecto.Changeset.t()}
  def delete_product_category(%ProductCategory{} = category) do
    Repo.delete(category)
  end

  @doc "Returns an empty changeset for a product category."
  @spec change_product_category(ProductCategory.t(), map()) :: Ecto.Changeset.t()
  def change_product_category(%ProductCategory{} = category, attrs \\ %{}) do
    ProductCategory.changeset(category, attrs)
  end

  # ---------------------------------------------------------------------------
  # Stock adjustments (merma / ajuste manual)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the adjustment history for a product, newest first.
  Preloads the user who made the adjustment.
  """
  def list_adjustments_for_product(product_id, limit \\ 50) do
    from(a in StockAdjustment,
      where: a.product_id == ^product_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: :adjusted_by
    )
    |> Repo.all()
  end

  @doc "Returns the most recent adjustments across all products."
  def list_recent_adjustments(limit \\ 100) do
    from(a in StockAdjustment,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: [:adjusted_by, :product]
    )
    |> Repo.all()
  end

  @doc """
  Creates a stock adjustment and updates the product's stock_quantity atomically.
  `attrs` must include :product_id, :quantity (negative = loss), and :reason.
  `user_id` is the id of the user registering the adjustment (may be nil).
  """
  def create_stock_adjustment(attrs, user_id \\ nil) do
    attrs_with_user = Map.put(attrs, :adjusted_by_id, user_id)

    Repo.transaction(fn ->
      changeset = StockAdjustment.changeset(%StockAdjustment{}, attrs_with_user)

      adj =
        case Repo.insert(changeset) do
          {:ok, a}    -> a
          {:error, cs} -> Repo.rollback(cs)
        end

      quantity = adj.quantity

      from(p in Product, where: p.id == ^adj.product_id)
      |> Repo.update_all(inc: [stock_quantity: quantity])

      adj
    end)
  end

  @doc "Returns an empty changeset for a stock adjustment form."
  def change_stock_adjustment(attrs \\ %{}) do
    StockAdjustment.changeset(%StockAdjustment{}, attrs)
  end

  @doc "Human-readable labels for adjustment reasons."
  def adjustment_reason_label("caducidad"),    do: "Caducidad"
  def adjustment_reason_label("derrame"),      do: "Derrame / rotura"
  def adjustment_reason_label("robo"),         do: "Robo / extravío"
  def adjustment_reason_label("ajuste_manual"),do: "Ajuste de inventario"
  def adjustment_reason_label("otro"),         do: "Otro"
  def adjustment_reason_label(r),              do: r

  def adjustment_reasons do
    [
      {"Caducidad",             "caducidad"},
      {"Derrame / rotura",      "derrame"},
      {"Robo / extravío",       "robo"},
      {"Ajuste de inventario",  "ajuste_manual"},
      {"Otro",                  "otro"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Private broadcast helpers
  # ---------------------------------------------------------------------------

  defp broadcast_supplier_change({:ok, supplier} = result) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:suppliers", {:supplier_changed, supplier})
    result
  end

  defp broadcast_supplier_change(error), do: error

  defp broadcast_product_change({:ok, product} = result) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, product})
    result
  end

  defp broadcast_product_change(error), do: error

  # Broadcast a product_changed event using the product_id (for variant mutations).
  defp broadcast_product_change_for_product({:ok, record}, product_id) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, %{id: product_id}})
    {:ok, record}
  end

  defp broadcast_product_change_for_product(error, _product_id), do: error
end
