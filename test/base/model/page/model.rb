module Model
  class Page

    include DataMapper::Resource

    property :id, Serial
    property :name, String
    property :label, String
    property :url, String

    property :meta_title, String
    property :meta_description, String
    property :meta_keywords, String

    property :callback_a_test, String
    property :callback_z_test, String

    property :content, Text
    property :active, Integer
  end
end