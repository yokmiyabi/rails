class Post < ActiveRecord::Base
 validates :title, :presence => true, :length => {:maximum => 20}
 has_many :comments

  scope :title_or_body_matches, lambda {|q| where 'title like :q or body like :q', :q => "%#{q}%"}

end
