defmodule CRC.Repo.Migrations.CreateCrm do
  @moduledoc """
  Módulo de Clientes + Lealtad (contexto `CRC.CRM`).

    * `customers`            — ficha del cliente frecuente (sin auth)
    * `customer_visits`      — una fila por comanda cerrada asociada a un cliente
    * `loyalty_rewards`      — configuración de niveles (visitas) y de cumpleaños
    * `loyalty_redemptions`  — evento: recompensa ganada / redimida (con snapshots)

  Además cablea `customer_id` en `orders` y `packages`, y
  `loyalty_redemption_id` en `order_items` (para marcar las líneas de cortesía).

  Producción corre PostgreSQL 12: nada de `gen_random_uuid()` ni `pgcrypto`.
  """
  use Ecto.Migration

  def change do
    create table(:customers) do
      add :name, :string, null: false
      add :phone, :string
      add :email, :string
      add :birthday, :date
      add :notes, :text
      add :active, :boolean, default: true, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:customers, [:phone])
    create index(:customers, ["lower(name)"], name: :customers_lower_name_index)
    create index(:customers, [:active])

    alter table(:orders) do
      add :customer_id, references(:customers, on_delete: :nilify_all)
    end

    create index(:orders, [:customer_id])

    create table(:customer_visits) do
      add :customer_id, references(:customers, on_delete: :delete_all), null: false
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :recorded_at, :utc_datetime, null: false
      add :recorded_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customer_visits, [:order_id])
    create index(:customer_visits, [:customer_id])

    create table(:loyalty_rewards) do
      add :kind, :string, null: false
      add :name, :string, null: false
      add :visits_required, :integer
      add :benefit, :string, null: false
      add :benefit_menu_item_id, references(:menu_items, on_delete: :nilify_all)
      add :repeatable, :boolean, default: true, null: false
      add :birthday_window_days, :integer, default: 0, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_rewards, [:kind, :active])

    create unique_index(:loyalty_rewards, [:kind],
             where: "kind = 'birthday' AND active",
             name: :loyalty_rewards_one_active_birthday_index
           )

    create unique_index(:loyalty_rewards, [:visits_required],
             where: "kind = 'visits'",
             name: :loyalty_rewards_unique_visits_required_index
           )

    create table(:loyalty_redemptions) do
      add :customer_id, references(:customers, on_delete: :delete_all), null: false
      add :loyalty_reward_id, references(:loyalty_rewards, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :benefit_snapshot, :string, null: false
      add :visits_required_snapshot, :integer
      add :cycle, :integer, default: 1, null: false
      add :earned_at, :utc_datetime, null: false
      add :earned_at_visit_count, :integer
      add :status, :string, default: "earned", null: false
      add :redeemed_at, :utc_datetime
      add :redeemed_by_id, references(:users, on_delete: :nilify_all)
      add :order_id, references(:orders, on_delete: :nilify_all)
      add :birthday_year, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_redemptions, [:customer_id, :status])

    create unique_index(:loyalty_redemptions, [:customer_id, :loyalty_reward_id, :cycle],
             where: "kind = 'visits'",
             name: :loyalty_redemptions_unique_visits_cycle_index
           )

    create unique_index(:loyalty_redemptions, [:customer_id, :birthday_year],
             where: "kind = 'birthday'",
             name: :loyalty_redemptions_unique_birthday_year_index
           )

    alter table(:order_items) do
      add :loyalty_redemption_id, references(:loyalty_redemptions, on_delete: :nilify_all)
    end

    create index(:order_items, [:loyalty_redemption_id])

    alter table(:packages) do
      add :customer_id, references(:customers, on_delete: :delete_all)
    end

    create index(:packages, [:customer_id])
  end
end
