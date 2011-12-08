class CreateComments < ActiveRecord::Migration
  def change
    create_table :comments do |t|
      t.references :post
      t.string :comment
      t.string :name

      t.timestamps
    end
    add_index :comments, :post_id
  end
end
