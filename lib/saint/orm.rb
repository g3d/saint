module Saint

  module ORMQuery

    def sql operator, column, val
      {conditions: ['%s %s ?' % [column, operator], val]}
    end

    def eql column, val = nil
      {column => val}
    end

    def like column, val = nil
      {column.like => val}
    end

    def gt column, val = nil
      {column.gt => val}
    end

    def gte column, val = nil
      {column.gte => val}
    end

    def lt column, val = nil
      {column.lt => val}
    end

    def lte column, val = nil
      {column.lte => val}
    end

    def not column, val = nil
      {column.not => val}
    end

    def limit limit, offset = nil
      {limit: limit}.merge(offset ? {offset: offset} : {})
    end

    def order map = {}
      order = map.keys.map { |c| c.send(map[c]) }.compact
      order.size > 0 ? {order: order} : {}
    end

  end

  module ORMUtils

    PROPERTIES_MAP = {
        'binary' => 'text',
        'boolean' => true,
        'date' => true,
        'date_time' => true,
        'decimal' => 'string',
        'float' => 'string',
        'integer' => 'string',
        'string' => true,
        'text' => true,
        'time' => true,
    }

    RELATIONS_MAP = {
        'ManyToOne' => :belongs_to,
        'OneToMany' => :has_n,
        'OneToOne' => :has_n,
        'ManyToMany' => :has_n,
    }

    class << self

      include ORMQuery
      include Saint::Inflector

      def relations model
        skip_models = model.relationships.map { |r| (r.through.target_model if r.respond_to?(:through)) }.compact
        model.relationships.reject { |r| skip_models.include?(r.target_model) }.map do |r|
          (type = RELATIONS_MAP[r.class.name.split('::')[2]]) &&
              [type, r.field.to_sym, r.target_model, (r.through.target_model if r.respond_to?(:through))].compact
        end.compact
      end

      def primary_key model
        if key = model.properties.select{|p| demodulize(p.class) == 'Serial'}.first
          key.name
        end
      end

      def properties model, exclude_keys = true
        properties = model.properties
        properties = properties.reject { |p| p.name.to_s =~ /_id$/ } if exclude_keys
        properties.inject({}) do |f, c|
          (primitive = underscore(demodulize(c.class))) &&
              (type = PROPERTIES_MAP[primitive]) &&
              (f||{}).update(c.name => type == true ? primitive : type)
        end
      end

      def quote_column column, model
        property = model.properties.select { |p| p.name == column }.first
        model.repository(model.repository_name).adapter.property_to_column_name(property, false)
      end

      def finalize
        DataMapper.finalize
      end
    end
  end

  module ORMMixin

    include ORMQuery

    attr_reader :model

    def initialize model, *controller_instance_and_or_subset

      @model, @subset, @controller_instance = model, Hash.new, nil
      controller_instance_and_or_subset.each { |a| a.is_a?(Hash) ? @subset.update(a) : @controller_instance = a }
      @before, @after = Hash.new, Hash.new
    end

    def first filters = {}
      db { model.first(filters.merge @subset) }
    end

    def first_or_create filters = {}
      db { model.first_or_create(filters.merge @subset) }
    end

    def filter filters = {}
      db { model.all(filters.merge @subset) }
    end

    def count filters = {}
      db { model.count(filters.merge @subset) }
    end

    def new data_set = {}
      db { model.new(data_set.merge @subset) }
    end

    def create data_set = {}
      db { model.create(data_set.merge @subset) }
    end

    def save row
      @subset.each_pair { |k, v| row[k] = v }
      return db(__method__, row) { row.save; row } if row.valid?
      [nil, dump_exception(row.errors)]
    end

    def update row, data_set
      row.reload if row.dirty?
      row.save if row.new?
      data_set.merge(@subset).each_pair { |k, v| row[k] = v }
      return db(:save, row) { row.save; row } if row.valid?
      [nil, dump_exception(row.errors)]
    end

    def delete filters = {}
      rows, errors = db { model.all(filters.merge @subset) }
      return [nil, errors] if errors.size > 0
      rows.map do |row|
        break if @errors.size > 0
        db(__method__, row) { row.destroy! }
      end
      [@result, @errors]
    end

    def quote_column column
      ORMUtils.quote_column column, model
    end

    def properties
      ORMUtils.properties model
    end

    def subset subset
      @subset = subset
    end

    # define callbacks to be executed before given actions,
    # or before/after any action if no actions given.
    def before *actions, &proc
      if proc
        actions = ['*'] if actions.size == 0
        actions.each { |a| @before[a] = proc }
      end
      @before
    end

    # (see #before)
    def after *actions, &proc
      if proc
        actions = ['*'] if actions.size == 0
        actions.each { |a| @after[a] = proc }
      end
      @after
    end

    private

    def db operation = nil, row = nil, &proc
      @result, @errors = nil, Array.new
      scope = @controller_instance || self
      begin

        if row
          before.select { |o, p| [operation, '*'].include?(o) }.each_value do |p|
            scope.instance_exec row, operation, &p
          end
        end

        @result = proc.call

        unless operation == :delete
          if row
            after.select { |o, p| [operation, '*'].include?(o) }.each_value do |p|
              scope.instance_exec row, operation, &p
            end
          end
        end

      rescue => e
        @errors = dump_exception e
      end
      [@result, @errors]
    end

    def dump_exception e
      errors = []
      case
        when e.respond_to?(:errors)
          errors = e.errors
        when e.respond_to?(:each_pair)
          e.each_pair do |k, v|
            errors << [k, v].map { |o| o.respond_to?(:flatten) ? o.flatten : o }.join(': ')
          end
        when e.respond_to?(:each)
          errors = e
        else
          errors = [e.to_s]
      end
      errors.flatten
    end

  end

  class ORM
    include Saint::ORMMixin
  end

end
