defmodule CRC.Inventory do
  @moduledoc """
  Bounded context for inventory management.

  Handles suppliers (proveedores) and products/supplies (insumos).
  Products track stock levels and alert when below minimum threshold.
  """

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Inventory.Product
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

  @doc "Returns all products with their supplier preloaded, ordered by name."
  @spec list_products() :: [Product.t()]
  def list_products do
    Repo.all(
      from p in Product,
        left_join: s in assoc(p, :supplier),
        preload: [supplier: s],
        order_by: [asc: p.category, asc: p.name]
    )
  end

  @doc "Returns products with stock at or below minimum threshold."
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

  @doc "Gets a product by id. Raises if not found."
  @spec get_product!(integer()) :: Product.t()
  def get_product!(id) do
    Product
    |> Repo.get!(id)
    |> Repo.preload(:supplier)
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
end
