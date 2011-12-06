class AddDescriptionToItems < ActiveRecord::Migration
  def change
    add_column :items, :description, :string
  end
end
