Saint - Simple Admin Interface
---

Saint allow developers to easily manage existing ORM models(currently only DataMapper supported).

It is aimed to automatize the backend building process, by creating **Summary** and **CRUD** pages.

**Install:**

    $ gem install saint

Before any setup, let Saint know the model to be managed.

**Model to be managed:**

    class PageModel
        include DataMapper::Resource
        property :id, Serial
        property :name, String
    end

**Saint setup:**

    class Page
        include Saint::Api
        http.map :pages
        saint.model PageModel
        saint.column :name
    end

Saint expects given model to have :id as primary key, but allow to set a custom key,
by passing it as second argument or by using #saint.pkey:

    class Page
        include Saint::Api

        saint.model Model::Page, :uid
        # or
        saint.pkey :uid
    end

**Deploy:**

    app = Presto::App.new
    app.mount Page
    app.run

###CRUD Pages

Aimed to edit columns and associations.

**Columns**

Saint allow to draw HTML columns of various types and options using pure Ruby code.

Text field:

    saint.column :name
    # UI output: <input type="text" name=":name" />

Textarea field:

    saint.column :about, :text
    # UI output: <textarea name="about" style="width: 100%;"></textarea>


To have some column excluded from CRUD pages, set :crud option to false:

    saint.column :date do
        crud false
    end

[More on Columns](saint/blob/master/Columns.md)

**Associations**

Saint does support *"belongs to"*, *"has N"* and *"has N through"* associations.

    class Game
        include Saint::Api

        saint.model Model::Game

        # game belongs to edition
        saint.belongs_to :edition, Model::Edition

        # game has N goals
        saint.has_n :goals, Model::Goal

        # game has N scorers(players), through PlayersScorers model
        saint.has_n :scorers, Model::Player, Model::PlayersScorers
    end

There are also tree association, when some item may belong to another item of same model.

    saint.is_tree

[More on Associations](saint/blob/master/Associations.md)

[More on CRUD pages](saint/blob/master/CRUDPages.md)

###Summary pages

**Columns**

All the columns defined above, will be displayed on Summary pages,
in the order they was defined.

To exclude some column, set :summary option to false:

    saint.column :date do
        summary false
    end

**Order**

Saint will extract and display model items in the order ORM returns them.

*saint.order* allow to display items in the desired way:

    saint.order :date, :desc
    saint.order :name
    # SQL: ORDER BY date DESC, name

**Pagination**

By default, Saint will display 10 items per page.

Use *saint.items_per_page* to override this:

    saint.items_per_page 50
    # or just
    saint.ipp 50

[More on Summary pages](saint/blob/master/SummaryPages.md)

###Menu

Saint will automatically build an menu containing links to all pages.

Any class including *Saint::Api* will be automatically included in menu.

Menu label is defaulted to node's header, set by *saint.header*:

    saint.menu.label 'CMS Pages'
    # now menu label is "CMS Pages"

To have menu displayed, simply call *Saint::Menu.new.render* in your layout:

    <body>
        <%= Saint::Menu.new.render %>
        ...
    </body>

[More on Menus](saint/blob/master/Menu.md)

###File Manager

Saint comes with a built-in file manager.

Simply let Saint know the full path to folder and it will turn a class into a fully fledged file manager

    class FileManager

        include Saint::Api
        http.map 'file-manager'

        saint.fm do
            root '/full/path/to/folder'
        end

    end

[More on File Manager](saint/blob/master/FileManager.md)


###Opts Manager

Saint also has an built-in Opts Manager, which is a simple UI for editing predefined options.

Any class may include Saint::OptsApi and get an extra Api, via #opts method.

Options defined inside Opts Manager can be accessed by #opts Api.

    # creating Opts Manager UI
    class Admin
        include Saint::Api

        saint.opts do
            opt :items_per_page, default: 10
        end
    end

    # making use of Opts Api in some frontend class
    class Pages
        include Saint::OptsApi

        # lets saint know what Opts Manager to use
        opts Admin

        # now you can use opts.items_per_page anywhere in your class and its instances.

        opts.items_per_page # will return 10, until you edit it via UI

        def index
            opts.items_per_page # available in class instances as well
        end
    end

[More on Opts Manager](saint/blob/master/OptsManager.md)

###rb_wrapper

If you use :rte type for some column and the content contains the tags
that conflicts with editor, you can replace that tags when displaying content in editor
and restore them when content saved to db.

Saint allow to do this seamlessly:

    saint.rb_wrapper true

With rb_wrapper enabled, Saint will replace tags as follows:

*   <%== code %> will be converted to :!{:== code :}:
*   <%= code %> will be converted to :!{:= code :}:
*   <% code %> will be converted to :!{: code :}:

All tags will be restored when content saved to db.
