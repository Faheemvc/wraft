defmodule WraftDoc.Repo.Migrations.RefactorRoleBasedAccessControlTables do
  use Ecto.Migration

  def change do
    drop(table(:permission))

    create table(:permission, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string)
      add(:resource, :string)
      add(:action, :string)

      timestamps()
    end
  end
end
