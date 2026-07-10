defmodule CRC.Loyalty do
  @moduledoc false

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Loyalty.LoyaltyVisit

  @spec list_visits(integer()) :: [LoyaltyVisit.t()]
  def list_visits(user_id) do
    LoyaltyVisit
    |> where([v], v.user_id == ^user_id)
    |> order_by([v], desc: v.inserted_at)
    |> Repo.all()
  end

  @spec count_visits(integer()) :: non_neg_integer()
  def count_visits(user_id) do
    LoyaltyVisit
    |> where([v], v.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @spec record_visit(map()) :: {:ok, LoyaltyVisit.t()} | {:error, Ecto.Changeset.t()}
  def record_visit(attrs) do
    %LoyaltyVisit{}
    |> LoyaltyVisit.changeset(attrs)
    |> Repo.insert()
  end
end
