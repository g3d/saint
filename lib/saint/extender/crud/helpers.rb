module Saint
  class CrudExtender

    def helpers
      @node.class_exec do

        private

        def render_elements elements, opts = {}
          layout = opts[:layout] || (opts[:node]||self).saint.column_layout
          html = ''
          elements.each_pair do |el, el_html|
            if el.grid
              grid_elements = elements.select { |k, v| k.grid && k.grid == el.grid && elements.delete(k) }
              html << (render_grid(el.grid, grid_elements, opts) || '')
            else
              context = {layout: layout, el: el, el_html: el_html, row: opts[:row]}
              html << saint_view.render_view('edit/element', context)
            end
          end
          html
        end

        def render_grid grid_name, elements, opts = {}
          if grid = (opts[:node]||self).saint.grids[grid_name]
            context = {grid: grid, elements: elements, opts: opts}
            saint_view.render_view('edit/grid', context)
          end
        end

        def crud_columns columns, row = nil
          columns.select { |n, c| c.crud? }.values.inject({}) do |map, column|
            element, value = column, column.crud_value(row, self)
            html = column.type ?
                saint_view.render_view('edit/elements/%s' % column.type, element: element, value: value) :
                value
            map.update(column => html)
          end
        end

        def summary_columns implicit_columns, explicit_columns = nil

          columns = Array.new
          if explicit_columns.is_a?(Array)
            explicit_columns.each do |c|
              next unless column = implicit_columns[c.to_sym]
              columns << column
            end
          end
          if columns.size == 0
            implicit_columns.select { |n, c| c.summary? }.each_value do |column|
              next if column.password?
              columns << column
            end
          end
          columns
        end

      end

    end

  end
end
