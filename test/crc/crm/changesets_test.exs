defmodule CRC.CRM.ChangesetsTest do
  use CRC.DataCase, async: true

  alias CRC.CRM.{Customer, CustomerVisit, LoyaltyReward, LoyaltyRedemption}

  describe "Customer.changeset/2" do
    test "requires name and phone" do
      cs = Customer.changeset(%Customer{}, %{})

      assert %{name: ["no puede estar en blanco"], phone: ["no puede estar en blanco"]} =
               errors_on(cs)
    end

    test "title-cases the name and downcases the email" do
      cs =
        Customer.changeset(%Customer{}, %{
          name: "ANA lópez",
          phone: "5512345678",
          email: "  ANA@Example.COM "
        })

      assert cs.valid?
      assert get_change(cs, :name) == "Ana López"
      assert get_change(cs, :email) == "ana@example.com"
    end

    test "rejects a malformed email" do
      cs =
        Customer.changeset(%Customer{}, %{name: "Ana", phone: "55", email: "not-an-email"})

      assert %{email: ["tiene formato inválido"]} = errors_on(cs)
    end

    test "email is optional" do
      cs = Customer.changeset(%Customer{}, %{name: "Ana", phone: "55"})
      assert cs.valid?
    end
  end

  describe "LoyaltyReward.changeset/2" do
    test "visits tier requires a positive visits_required" do
      assert %{visits_required: [_]} =
               errors_on(
                 LoyaltyReward.changeset(%LoyaltyReward{}, %{
                   kind: "visits",
                   name: "N",
                   benefit: "Café"
                 })
               )

      assert %{visits_required: [_]} =
               errors_on(
                 LoyaltyReward.changeset(%LoyaltyReward{}, %{
                   kind: "visits",
                   name: "N",
                   benefit: "Café",
                   visits_required: 0
                 })
               )
    end

    test "birthday reward nulls out visits_required" do
      cs =
        LoyaltyReward.changeset(%LoyaltyReward{}, %{
          kind: "birthday",
          name: "Cumpleaños",
          benefit: "Postre gratis",
          visits_required: 6
        })

      assert cs.valid?
      assert get_field(cs, :visits_required) == nil
    end

    test "rejects an unknown kind" do
      assert %{kind: [_]} =
               errors_on(
                 LoyaltyReward.changeset(%LoyaltyReward{}, %{
                   kind: "weird",
                   name: "N",
                   benefit: "X"
                 })
               )
    end
  end

  describe "LoyaltyRedemption.changeset/2" do
    test "requires the snapshot fields" do
      cs = LoyaltyRedemption.changeset(%LoyaltyRedemption{}, %{})

      errors = errors_on(cs)
      assert errors[:customer_id]
      assert errors[:benefit_snapshot]
      assert errors[:earned_at]
    end

    test "accepts a valid visits redemption" do
      cs =
        LoyaltyRedemption.changeset(%LoyaltyRedemption{}, %{
          customer_id: 1,
          kind: "visits",
          benefit_snapshot: "Café gratis",
          cycle: 1,
          earned_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "earned"
        })

      assert cs.valid?
    end
  end

  describe "CustomerVisit.changeset/2" do
    test "requires customer, order and recorded_at" do
      cs = CustomerVisit.changeset(%CustomerVisit{}, %{})

      errors = errors_on(cs)
      assert errors[:customer_id]
      assert errors[:order_id]
      assert errors[:recorded_at]
    end
  end
end
