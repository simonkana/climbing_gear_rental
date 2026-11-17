class AddImageUrlToEquipment < ActiveRecord::Migration[8.1]
  def change
    add_column :equipment, :image_url, :string, limit: 2048
    add_check_constraint :equipment, "image_url IS NULL OR image_url LIKE 'https://%'",
      name: "equipment_image_url_https"
  end
end
