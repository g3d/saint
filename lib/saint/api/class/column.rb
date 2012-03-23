module Saint
  class ClassApi

    # given model may contain many columns,
    # however, in most cases, not all of them should be managed by Saint.
    #
    # @example display :name in both Summary and CRUD pages. type defaulted to String
    #    saint.column :name
    #
    # @example show the :date only on CRUD pages
    #    saint.column :date, summary: false
    #
    # @example drop-down selector
    #    saint.column :color, :select, options: ['red', 'green', 'blue']
    #
    # @example display date in human format on summary pages
    #    saint.column :date do
    #      value do |val|
    #        val.strftime('%b %d, %Y') if summary?
    #      end
    #    end
    #
    # @example display name with email on summary pages
    #    saint.column :name do
    #      value do |val|
    #        '%s <%s>' % [val, row.email] if summary?
    #      end
    #    end
    #
    # @param [Symbol] name
    # @param [Symbol, Hash] *type_and_or_opts
    # @param [Proc] &proc
    def column name, *type_and_or_opts, &proc
      return unless configurable?
      @grid && @grid_columns += 1
      type, opts = nil, {}
      type_and_or_opts.each { |a| a.is_a?(Hash) ? opts.update(a) : type = a }
      column = ::Saint::Column.new(name, type, opts.merge(rbw: @controller.saint.rbw, grid: @grid), &proc)
      @columns[column.name] = column
    end

    alias property column

    # by default, UI use a fieldset to display elements.
    # use this method to define a custom layout.
    #
    # @example set custom layout for all elements
    #
    #    # default layout for an text element looks like:
    #    # <fieldset><legend>[label]</legend>[field]</fieldset>
    #    # use saint.column_layout to set custom layout
    #
    #    saint.column_layout '<div>[label]: [field]</div>'
    #
    # @param [String] layout
    #   should contain [label] and [field] snippets
    def column_layout layout = nil
      @column_layout = layout if configurable? && layout
      @column_layout
    end

    # by default, columns are delimited by line break.
    # this method allow to display N columns inline.
    #
    # @example
    #    saint.grid do
    #      column :name
    #      column :age
    #    end
    #
    # @example
    #    saint.grid header: 'some html' do
    #      column :name
    #      column :age
    #      column :email
    #    end
    #
    # @param [Array] *name_and_or_opts
    # @options name_and_or_opts [String] :header
    # @options name_and_or_opts [String] :footer
    # @param [Proc] &proc
    def grid *name_and_or_opts, &proc
      return unless configurable?
      name, opts = nil, Hash.new
      name_and_or_opts.each { |a| a.is_a?(Hash) ? opts.update(a) : name = a }
      id = Digest::MD5.hexdigest(name.to_s + proc.to_s)
      name ||= id
      if proc
        @grid, @grid_columns = name, 0
        self.instance_exec &proc
        @grid = nil
      end
      columns = opts.delete(:columns) || @grid_columns || 2
      grids[name] = Struct.new(:id, :name, :columns, :opts).new(id, name, columns, opts)
    end

    # returns earlier defined grids
    def grids
      @grids ||= Hash.new
    end

    # by default, Saint will manage all properties found on given model.
    # use `columns` inside #model block to limit them to specified ones.
    # if first argument is false [Boolean], no columns will be built automatically.
    # that's for case when you want to declare columns manually.
    #
    # @example build only :title and :meta_*
    #    saint.model SomeModel do
    #      columns :title, /^meta_/
    #    end
    #
    # @example do not build any columns, i'll manually declare them.
    #    saint.model SomeModel do
    #      columns false
    #    end
    #
    def columns *args
      if args.size > 0 && configurable?
        raise 'please call %s only inside #model block' % __method__ if model_defined?
        return @columns_opted = false if args.first == false
        @columns_opted = args
      end
    end

    # by default, Saint will manage all properties found on given model(except primary and foreign keys)
    # to ignore some of them, simply use `columns_ignored` inside #model block
    #
    # @controller this method should be called inside #model block
    #
    # @example manage all columns but :meta_* and :visits
    #    saint.model SomeModel do
    #      columns_ignored /^meta_/, :visits
    #    end
    #
    # @param [Array] *columns
    def columns_ignored *args
      if args.size > 0 && configurable?
        raise 'please call %s only inside #model block' % __method__ if model_defined?
        @columns_ignored = args
      end
    end

    def column_instances
      @columns
    end

    private
    # automatically build columns based on properties found on given model
    def build_columns
      return unless configurable?
      return if @columns_opted == false
      selector(ORMUtils.properties(model), @columns_opted, @columns_ignored).each do |c|
        name, type = c
        args = name, type
        args << {summary: false} if type == 'text'
        column *args
      end
    end

  end

  class Column

    include Saint::Utils

    OPTS = [
        :summary, :crud, :save,
        :label, :tag, :rbw, :html,
        :options, :multiple, :size, :join_with, :required, :default,
        :width, :height, :css_style, :css_class,
        :layout, :layout_style, :layout_class,
    ]

    attr_reader :id, :name, :type, :grid, :grid_width

    # helpers for value related proc.
    # @example
    #    saint.column :name do
    #      value { |val| scope == :summary ? "#{val}, created on #{row.date}" : val }
    #    end
    attr_reader :row, :scope

    # build new column
    #
    # @param [Symbol] name
    # @param [Symbol] type
    # @param [Hash] opts
    # @options opts [Boolean] summary
    # @options opts [Boolean] crud
    # @options opts [Boolean] save
    # @options opts [Symbol, String] label
    # @options opts [Symbol] tag
    # @options opts [Boolean] rbw
    # @options opts [Boolean] html
    # @options opts [Hash, Array] options
    # @options opts [Boolean] multiple
    # @options opts [Integer] size
    # @options opts [String] join_with
    # @options opts [Boolean] required
    # @options opts [Symbol, String] default
    # @options opts [Integer, String] width
    # @options opts [Integer, String] height
    # @options opts [String] css_style
    # @options opts [String, Symbol] css_class
    # @options opts [Symbol, String] layout
    # @options opts [String] layout_style
    # @options opts [Symbol, String] layout_class
    # @param [Proc] &proc
    def initialize name, type = nil, opts = {}, &proc

      OPTS.each do |opt|
        opts.has_key?(opt) && instance_variable_set('@%s' % opt, opts[opt])
      end

      proc && instance_exec(&proc)

      # default type is string
      @type = (type || 'string').to_s.downcase

      instance_variable_defined?(:@summary) || @summary = (text? || rte? ? false : true)
      instance_variable_defined?(:@crud) || @crud = true
      instance_variable_defined?(:@save) || @save = (plain? ? false : true)

      # is current column a part of a grid
      @grid = opts[:grid]

      @id = '%s_%s' % [name, Digest::MD5.hexdigest(@proc.to_s)]
      @name = name.to_sym

      @label ||= Saint::Inflector.titleize(@name)

      @width = '%spx' % @width if @width.is_a?(Numeric)
      @height = '%spx' % @height if @height.is_a?(Numeric)

      width, height = @width, @height

      if @grid
        @grid_width = @width
        width = '100%'
      end

      width = @width if select? || checkbox? || radio? || password? || boolean?
      width ||= '100px' if date? || date_time? || time?
      height ||= '100px' if text?

      @css_style = '%s %s %s' % [
          @css_style,
          ('width: %s;' % width if width),
          ('height: %s;' % height if height)
      ]
    end

    # should the column be shown on Summary pages?
    # true by default
    def summary *args
      @summary = args.first if args.size > 0
    end

    # true when column shown on Summary pages
    def summary?
      @scope ? @scope == :summary : @summary
    end

    # should the column be shown on Crud pages?
    # true by default
    def crud *args
      @crud = args.first if args.size > 0
    end

    # true when column shown on CRUD pages
    def crud?
      @scope ? @scope == :crud : @crud
    end

    # should the column be used when object persisted to db?
    # true by default
    def save *args
      @save = args.first if args.size > 0
    end

    def save?
      @scope ? @scope == :save : (plain? && @save.nil? ? false : @save)
    end

    # if set to true, item wont be saved if field is empty.
    # false by default
    def required *args
      @required = args.first if args.size > 0
    end

    def required?
      @required
    end

    # should the select-multiple drop-downs allow multiple options selection?
    # false by default
    def multiple *args
      @multiple = args.first if args.size > 0
      @multiple
    end

    def multiple?
      @multiple
    end

    # string used to join values for checkbox and select-multiple columns.
    # a coma will be used by default
    def join_with str = nil
      @join_with = str if str
      @join_with || ', '
    end

    # indicates how much lines to display for select-multiple columns.
    # nil by default
    def size size = nil
      @size = size.to_i if size
      @size
    end

    # options to be used on select, radio and checkbox selectors
    def options *options
      if options.size > 0
        @options = {}
        options.each do |a|
          a.is_a?(Hash) ?
              @options.update(a) :
              a.is_a?(Array) ?
                  @options.update(Hash[a.zip(a)]) :
                  @options.update(a=>a)
        end
      end
      @options
    end

    # set value to be used when value for given column is nil.
    # for selectable columns, default option will be auto-selected,
    # on text columns, default text will be displayed.
    def default value = nil
      @default = value if value
      @default
    end

    # By default, Saint will use capitalized name for label:
    #
    #    saint.column :name
    #    # HTML: <fieldset><legend>Name</legend>...
    #
    # To have an custom label, use #label inside block:
    #
    #    saint.column :name do
    #      label "Author's Name"
    #    end
    #    # HTML: <fieldset><legend>Author's Name</legend>...
    def label label = nil
      @label = label if label
      @label
    end

    # if set to true, value wont be escaped
    def html *args
      @html = true if args.size > 0
      @html
    end

    def html?
      @html
    end

    # search/group columns by tags
    def tag tag = nil
      @tag = tag if tag
      @tag
    end

    def width val = nil
      @width = val if val
      @width
    end

    def height val = nil
      @height = val if val
      @height
    end

    def css_style val = nil
      @css_style = val if val
      @css_style
    end

    def css_class val = nil
      @css_class = val if val
      @css_class
    end

    # use a custom layout for current column.
    # also see {Saint::ClassApi#column_layout}, which set layout for all columns
    def layout val = nil
      @layout = val if val
      @layout
    end

    # use default layout but add this css style
    def layout_style val = nil
      @layout_style = val if val
      @layout_style
    end

    # use default layout but add this css class
    def layout_class val = nil
      @layout_class = val if val
      @layout_class
    end

    def select?
      @type == 'select'
    end

    def checkbox?
      @type == 'checkbox'
    end

    def radio?
      @type == 'radio'
    end

    def plain?
      @type == 'plain'
    end

    def boolean?
      @type == 'boolean'
    end

    def password?
      @type == 'password'
    end

    def text?
      @type == 'text'
    end

    def rte?
      @type == 'rte'
    end

    def date?
      @type == 'date'
    end

    def date_time?
      @type == 'date_time'
    end

    def time?
      @type == 'time'
    end

    # shortcut for `value row, :crud`
    def crud_value row = nil, controller_instance = nil
      value row, :crud, controller_instance
    end

    # shortcut for `value row, :summary`
    def summary_value row = nil, controller_instance = nil
      value row, :summary, controller_instance
    end

    # if block given, this method will set a proc to be executed when column value requested.
    # proc meaning is to modify given value, depending on given scope, and return modified version.
    # if proc returns nil, original value will be used.
    #
    # given block will receive back an single argument - current value.
    # block should modify value, if needed, and return it.
    # given block will have access to following helper methods:
    # *  #summary? - true if column is currently shown on Summary pages
    # *  #crud? - true if column is currently shown on CRUD pages
    # *  #save? - true if row going to be saved to db
    # *  #row - current row object
    # *  #scope - one of :summary, :crud, :save
    #
    # block is executed inside currently running controller,
    # so it have access to any of #http, #view, #admin Api methods.
    #
    # if row and scope given, this method will extract, modify if needed,
    # and return value for current column
    #
    # @param [Object] row_or_value
    # @param [Symbol] scope
    # @param [Proc] proc
    def value row_or_value = nil, scope = nil, controller_instance = nil, &proc

      return @value_proc = proc if proc

      # extracting value
      value = scope == :save ? row_or_value : (row_or_value||{})[@name]

      @row, @scope, @controller_instance = row_or_value, scope, controller_instance

      if @options && summary?
        value = @options[value] unless checkbox? || multiple?
      end

      if boolean? && summary?
        value = Saint::Utils::BOOLEAN_OPTIONS[value]
      end

      if @value_proc && val = self.instance_exec(value, &@value_proc)
        value = val
      end
      @row, @scope, @controller_instance = nil

      # passwords are not wrapped
      return value if password?
      return format_date__time(@type, value, scope == :summary) if date? || date_time? || time?

      @rbw && value = @rbw.wrap(value)
      value.is_a?(String) ? (html? ? value : escape_html(value)) : value
    end

    # giving access to active controller's methods, like http, view and any helpers
    def method_missing *args
      @controller_instance.send *args
    end

  end

end
