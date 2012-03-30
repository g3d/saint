module Saint
  class ClassApi

    include Saint::Utils
    include Saint::Inflector

    # initializing the configuration Api for given controller.
    #
    # @param [Object] controller
    def initialize controller

      @controller = controller
      @ipp = Saint.ipp
      @pkey = :id

      @columns = {}
      @columns_opted, @columns_ignored = [], []

      @belongs_to, @has_n = {}, {}
      @relations_opted, @relations_ignored = [], []

      @filters_opted, @filters_ignored = [], []
      @subsets = {}

      @header_args, @header_opts = [], {}

      @create, @update, @delete, @dashboard = true, true, true, true

      @before, @after = {}, {}

      @capabilities = {create: true, update: true, delete: true}

      @view_scope = self
    end

    # *  setting the Api model
    # *  setting the primary key
    # *  extending current controller by adding CRUD methods
    #
    # @param [Class] model
    #   should be an valid ORM model. for now only DataMapper ORM supported.
    # @param [Symbol] pkey
    #   the model primary key, `:id`
    # @param [Proc] proc
    def model model = nil, pkey = nil, &proc
      if configurable? && model
        @model = model
        @pkey = pkey if pkey
        self.instance_exec(&proc) if proc
        @model_defined = true
        build_associations
        build_columns
        build_filters
        extend_controller
      end
      @model
    end

    def model_defined?
      @model_defined
    end

    # define primary key.
    # also can be defined by passing it as second argument to {#model}
    #
    # @param [Symbol] key
    def pkey key = nil
      @pkey = key if configurable? && key
      @pkey
    end

    # self-explanatory
    def items_per_page n = nil
      @ipp = n.to_i if n
      @ipp
    end

    alias :ipp :items_per_page

    # define the header to be displayed in UI.
    # header is defaulted to pluralized class name.
    # 
    # @example
    #    class Page
    #      include Saint::Api
    #
    #      # as header is defaulted to pluralized class name,
    #      # Page.saint.h will return "Pages"
    #
    #      # setting custom header label:
    #      saint.header label: 'CMS Pages'
    #      # now Page.saint.h and Page.saint.h(page) will return "CMS Pages"
    #
    #      # setting custom header for defined pages:
    #      saint.header :name, ' (by #author.name)'
    #      # now Page.saint.h will return "Pages"
    #      # however, Page.saint.h(page) will return "Pages | page.name (by page.author.name)"
    #      # IMPORTANT! if page has no author, ' (by #author.name)' will be ignored,
    #      # and Page.saint.h(page) will return only "Pages | page.name"
    #
    #      # setting custom header for defined pages with custom label:
    #      saint.header '#name', ' (by #author.name)', label: 'CMS Pages'
    #      # now Page.saint.h will return "CMS Pages"
    #      # and Page.saint.h(page) will return "CMS Pages | page.name (by page.author.name)"
    #
    #      # setting custom header using a block with default label:
    #      saint.header do |page|
    #        if page
    #          "#{page.name} (by #{page.author.name})"
    #        end
    #      end
    #      # now Page.saint.h will return "Pages"
    #      # and Page.saint.h(page) will return "Pages: page.name (by page.author.name)"
    #
    #      # setting custom header using a block with custom label:
    #      saint.header label: 'CMS Pages' do |page|
    #        "#{page.name} (by #{page.author.name})" if page
    #      end
    #      # now Page.saint.h will return "CMS Pages"
    #      # and Page.saint.h(page) will return "CMS Pages | page.name (by page.author.name)"
    #
    #    end
    #
    def header *format_and_or_opts, &proc
      return unless configurable?
      format_and_or_opts.each do |a|
        a.is_a?(Hash) ? @header_opts.update(a) : @header_args << a
      end
      @header_proc = proc if proc
    end

    # evaluate earlier defined header.
    # (see #header)
    #
    # @example
    #
    #    class Page
    #      include Saint::Api
    #
    #      saint.header :name, ', by #author.name'
    #      # saint.h(page) for a page with author will return "Pages | page.name, by page.author.name"
    #      # saint.h(page, join: ' / ') for a page with author will return "Pages / page.name, by page.author.name"
    #      # saint.h(page, join: false) for a page with author will return ["Pages", page.name, by page.author.name]
    #      # saint.h(page) for a page without author will return "Pages | page.name"
    #      # saint.h(page, join: ' / ') for a page without author will return "Pages / page.name"
    #      # saint.h(page, join: false) for a page without author will return ["Pages", page.name]
    #
    #    end
    #
    # @param [Hash] *row_or_opts
    # @option row_or_opts [String] :label
    #   override the label set by #header
    # @option row_or_opts [String] :join
    #   the string to join label and header.
    #   if not provided, a coma will be used.
    #   if it is set to nil or false, an array of label and header snippets will be returned.
    def h *row_or_opts

      row, opts = nil, {}
      row_or_opts.each { |a| a.is_a?(Hash) ? opts.update(a) : row = a }

      label = opts.has_key?(:label) ? (escape_html(opts[:label]) if opts[:label]) : label()
      join = escape_html(opts.fetch :join, ', ')
      header = []

      if @header_proc
        header << escape_html(@header_proc.call(row).to_s)
      else
        if row && @header_args.size == 0
          # no snippets defined, so using first column
          header << escape_html(column_instances.first.last.value(row))
        end
        @header_args.each do |a|
          (s = column_format(a, row)) && s.strip.size > 0 && header << escape_html(s)
        end
      end

      if join
        h = [label, header.join].compact.join(join)
        if length = opts[:length]
          h = '%s...' % h[0, length] if h.size > length
        end
        return h
      end
      [label, *header].compact
    end

    # prohibit :create operation
    # @example
    #    saint.create false
    def create *args
      remove_capability __method__ if configurable? && args.size > 0
      check_capability __method__
    end

    # prohibit :update operation
    # @example
    #    saint.update false
    def update *args
      remove_capability __method__ if configurable? && args.size > 0
      check_capability __method__
    end

    # prohibit :delete operation
    # @example
    #    saint.delete false
    def delete *args
      remove_capability __method__ if configurable? && args.size > 0
      check_capability __method__
    end

    alias :remove :delete

    # callbacks to be executed before/after given ORM action(s).
    # if no actions given, callbacks will be executed before any action.
    #
    # proc will receive the managed row as first argument(except #destroy action)
    # and can update it accordingly.
    # performed action will be passed as second argument.
    # proc will be executed inside controller instance, so all Api available.
    #
    # available actions:
    # *  save - fires when new item created or existing item updated
    # *  delete - fires when an item deleted
    # *  destroy - fires when all items are deleted
    #
    # @param [Array] *actions
    # @param [Proc] &proc
    def before *actions, &proc
      if configurable? && proc
        actions = ['*'] if actions.size == 0
        actions.each { |a| @before[a] = proc }
      end
      @before
    end

    # (see #before)
    def after *actions, &proc
      if configurable? && proc
        actions = ['*'] if actions.size == 0
        actions.each { |a| @after[a] = proc }
      end
      @after
    end

    def render_assets
      @rendered_assets ||= saint_view.render_view 'assets'
    end

    def render_menu
      @rendered_menu ||= Menu.new.render
    end

    def render_dashboard scope, str = nil
      saint_view(scope).render_master_layout do
        "%s\n%s" % [saint_view(scope).render_view('dashboard'), str]
      end
    end

    # should the controller be displayed on dashboard?
    def dashboard *args
      @dashboard = args.first if args.size > 0
      @dashboard
    end

    # get the label earlier set by `header`
    def label opts = {}
      @label ||= escape_html((@header_opts[:label] || pluralize(titleize(demodulize(@controller)))).to_s)
      opts[:singular] ? singularize(@label) : @label
    end

    private
    def configurable?
      @controller.ctrl.configurable?
    end

    def extend_controller
      Saint::CrudExtender.new @controller
    end

    def remove_capability cap
      @capabilities[cap] = nil
    end

    def check_capability cap
      @capabilities[cap]
    end

    def selector default, opted, ignored, index = 0
      items = []
      if opted.size > 0
        default.each do |i|
          opted.each do |o|
            items << i if (o.is_a?(Regexp) ? i[index] =~ o : i[index] == o)
          end
        end
      elsif ignored.size > 0
        default.each do |i|
          items << i unless ignored.select { |o| (o.is_a?(Regexp) ? i[index] =~ o : i[index] == o) }.first
        end
      else
        items = default
      end
      items
    end

  end
end
