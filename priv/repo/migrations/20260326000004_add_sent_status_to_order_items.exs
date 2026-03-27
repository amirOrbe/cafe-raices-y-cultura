defmodule CRC.Repo.Migrations.AddSentStatusToOrderItems do
  use Ecto.Migration

  def up do
    # Items in already-sent/ready orders were implicitly sent — mark them accordingly
    execute("""
    UPDATE order_items oi
    SET status = 'sent'
    FROM orders o
    WHERE oi.order_id = o.id
      AND oi.status = 'pending'
      AND o.status IN ('sent', 'ready')
    """)
  end

  def down do
    execute("UPDATE order_items SET status = 'pending' WHERE status = 'sent'")
  end
end
