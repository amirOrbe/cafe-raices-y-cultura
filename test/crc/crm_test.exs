defmodule CRC.CRMTest do
  use CRC.DataCase, async: true

  alias CRC.CRM
  alias CRC.CRM.Customer

  import CRC.E2EFixtures

  describe "create_customer/2" do
    test "creates a customer, title-casing the name" do
      assert {:ok, %Customer{} = customer} =
               CRM.create_customer(%{name: "ana lópez", phone: "5512345678"})

      assert customer.name == "Ana López"
      assert customer.active == true
    end

    test "requires name and phone" do
      assert {:error, changeset} = CRM.create_customer(%{})
      assert %{name: [_], phone: [_]} = errors_on(changeset)
    end

    test "records the staff member who created it" do
      staff = create_admin()

      assert {:ok, customer} =
               CRM.create_customer(%{name: "Ana", phone: "55"}, staff)

      assert customer.created_by_id == staff.id
    end

    test "validates email format when present" do
      assert {:error, changeset} =
               CRM.create_customer(%{name: "Ana", phone: "55", email: "bad"})

      assert %{email: [_]} = errors_on(changeset)
    end

    test "broadcasts a customer_changed event" do
      CRM.subscribe_customers()
      {:ok, customer} = CRM.create_customer(%{name: "Ana", phone: "55"})
      assert_receive {:customer_changed, %Customer{id: id}}
      assert id == customer.id
    end
  end

  describe "update_customer/2" do
    test "updates fields" do
      customer = create_customer(%{name: "Ana"})
      assert {:ok, updated} = CRM.update_customer(customer, %{notes: "Le gusta el pan"})
      assert updated.notes == "Le gusta el pan"
    end
  end

  describe "search_customers/2" do
    test "matches partial name, case-insensitively" do
      create_customer(%{name: "María Fernanda", phone: "5511111111"})
      create_customer(%{name: "Pedro", phone: "5522222222"})

      assert [%Customer{name: "María Fernanda"}] = CRM.search_customers("fernan")
      assert [%Customer{name: "María Fernanda"}] = CRM.search_customers("MARÍA")
    end

    test "matches by phone fragment" do
      create_customer(%{name: "Pedro", phone: "5599887766"})
      assert [%Customer{name: "Pedro"}] = CRM.search_customers("9988")
    end

    test "excludes inactive customers" do
      customer = create_customer(%{name: "Inactiva", phone: "5500000000"})
      CRM.deactivate_customer(customer)
      assert CRM.search_customers("Inactiva") == []
    end

    test "returns [] for a blank query" do
      create_customer(%{name: "Ana"})
      assert CRM.search_customers("   ") == []
      assert CRM.search_customers(nil) == []
    end
  end

  describe "list_customers/1" do
    test "filters by status" do
      active = create_customer(%{name: "Activa"})
      inactive = create_customer(%{name: "Inactiva"})
      CRM.deactivate_customer(inactive)

      assert Enum.map(CRM.list_customers(), & &1.id) == [active.id]
      assert Enum.map(CRM.list_customers(status: :inactive), & &1.id) == [inactive.id]
      assert length(CRM.list_customers(status: :all)) == 2
    end
  end

  describe "deactivate/reactivate" do
    test "round-trips the active flag" do
      customer = create_customer()
      assert {:ok, %{active: false}} = CRM.deactivate_customer(customer)
      assert {:ok, %{active: true}} = CRM.reactivate_customer(CRM.get_customer!(customer.id))
    end
  end

  describe "delete_customer/1" do
    test "deletes a customer with no records" do
      customer = create_customer()
      assert {:ok, _} = CRM.delete_customer(customer)
      assert CRM.get_customer(customer.id) == nil
    end

    test "refuses to delete a customer that has orders" do
      customer = create_customer()
      order = create_order()
      associate_customer(order, customer)

      assert {:error, :has_records} = CRM.delete_customer(customer)
      assert CRM.get_customer(customer.id)
    end
  end

  describe "possible_duplicates/2" do
    test "finds other active customers sharing a phone" do
      a = create_customer(%{name: "Papá", phone: "5544332211"})
      b = create_customer(%{name: "Hija", phone: "5544332211"})

      assert [%{id: id}] = CRM.possible_duplicates("5544332211", b.id)
      assert id == a.id
    end
  end

  describe "birthday helpers" do
    test "list_customers_with_birthdays sorts by days until next birthday" do
      today = Date.utc_today()
      soon = create_customer(%{name: "Pronto", phone: "1", birthday: Date.add(today, 2)})
      later = create_customer(%{name: "Después", phone: "2", birthday: Date.add(today, 200)})
      _no_bday = create_customer(%{name: "Sin fecha", phone: "3"})

      ids = CRM.list_customers_with_birthdays() |> Enum.map(& &1.id)
      assert ids == [soon.id, later.id]
    end

    test "birthday_today? is true on the exact day" do
      today = ~D[2026-06-15]
      customer = %Customer{birthday: ~D[1990-06-15]}
      assert CRM.birthday_today?(customer, today)
      refute CRM.birthday_today?(%Customer{birthday: ~D[1990-06-16]}, today)
    end

    test "birthday_today? treats Feb 29 as Feb 28 in non-leap years" do
      leap_baby = %Customer{birthday: ~D[2000-02-29]}
      assert CRM.birthday_today?(leap_baby, ~D[2025-02-28])
      refute CRM.birthday_today?(leap_baby, ~D[2025-03-01])
      # In a leap year it still lands on the 29th
      assert CRM.birthday_today?(leap_baby, ~D[2024-02-29])
      refute CRM.birthday_today?(leap_baby, ~D[2024-02-28])
    end

    test "birthday_today? honors the window" do
      customer = %Customer{birthday: ~D[1990-06-15]}
      assert CRM.birthday_today?(customer, ~D[2026-06-17], 3)
      refute CRM.birthday_today?(customer, ~D[2026-06-19], 3)
      # window doesn't look backwards
      refute CRM.birthday_today?(customer, ~D[2026-06-13], 3)
    end
  end
end
