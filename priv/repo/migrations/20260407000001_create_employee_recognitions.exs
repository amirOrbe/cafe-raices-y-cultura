defmodule CRC.Repo.Migrations.CreateEmployeeRecognitions do
  use Ecto.Migration

  def change do
    create table(:employee_recognitions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :given_by_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      # "top_sales", "top_speed", "custom"
      add :note, :text
      add :period_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:employee_recognitions, [:user_id])
    create index(:employee_recognitions, [:period_date])
  end
end
