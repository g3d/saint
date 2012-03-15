module Ctrl
  class Author

    saint.model Model::Author do
      filters_ignored :password
    end

    saint.filter :date, :date, range: false

    #saint.columns_ignored :status

    saint.column :password, :password

    #saint.filter :name, logic: 'like'
    #saint.filter :status, :boolean
    #saint.filter :date, :date
    #saint.filter :date_time, :date_time
    #saint.filter :time, :time

    saint.header :name

    saint.order :id, :desc
    saint.has_n :pages, Model::Page do
      controller Ctrl::Page, true
      order :id, :desc
      column :name do
        label 'Name / Author'
        value do |val|
          val && (val + ((author = row.author) ? ' (%s)' % author.name : ''))
        end
      end
    end

    saint.belongs_to :country, Model::Country do
      controller Ctrl::Country, true
    end

  end
end
