module Saint
  class FmExtender

    include Saint::Utils
    include Saint::Inflector

    attr_reader :roots

    def initialize controller, opts = {}, &proc
      @controller, @opts, @roots = controller, opts, Array.new
      self.instance_exec &proc
      unless @controller.respond_to?(:index)
        root = @roots.first
        @controller.class_exec { http.before { http.redirect root.http.route } }
      end
    end

    def root root, opts = {}

      root = normalize_path root
      raise '"%s" should be a directory' % root unless File.directory?(root)

      controller, host = @controller, self

      label = opts.fetch :label, File.basename(root)
      url = label.to_s.gsub(/[^\w|\d|\-]/i, '_')
      edit_max_size = opts[:edit] || opts[:edit_max_size] || Saint::FileManager::EDIT_MAX_SIZE
      upload_max_size = opts[:upload] || opts[:upload_max_size] || Saint::FileManager::UPLOAD_MAX_SIZE

      @roots << (fm = controller.const_set 'Saint__Fm__' << url, Class.new)
      fm.class_exec do
        include Presto::Api
        include Saint::Utils
        http.map controller.http.route url
      end

      fs = fm.const_set :FileServer, Class.new
      fs.class_exec do

        include Presto::Api
        http.map fm.http.route('__file_server__')

        define_method :index do |*parts|
          http.send_file File.join(root, *parts).sub(/#{self.class.ext}$/, '')
        end

        class << self
          def ext
            '.saint-fs'.freeze
          end

          def [] path
            [http.route, ::Presto::Utils.normalize_path(path), ext].join
          end
        end
      end
      fm.class_exec do
        define_singleton_method :setup do
          @setup ||= Struct.new(:root, :roots, :url, :label, :file_server, :edit_max_size, :upload_max_size).
              new(root.freeze, host.roots.freeze, url.freeze, label.freeze, fs.freeze, edit_max_size.freeze, upload_max_size.freeze).freeze
        end

        define_method :setup do
          self.class.setup
        end
      end
      extend fm
    end

    def extend controller

      controller.class_exec do

        http.before do
          @helper = Saint::FileManager::Helper.new
          @active_dir, @active_file = active_dir?, active_file?
          @query_string = {dir: @active_dir}
          if (search_query = http.params['q']) && search_query.size > 1
            @query_string[:q] = search_query
          end
          @__meta_title__ = 'FileManager | %s | %s' % [setup.label, @active_dir]
        end

        view.engine Saint.view.engine
        view.ext Saint.view.ext
        view.layout :layout
        view.root Saint.view.root

        def index
          if @active_file
            template = :file
          else
            template = :index
            scan
            @active_dir.split('/').reject { |c| c == '.' || c.size == 0 }.each { |dir| scan dir }
          end
          view.render_master_layout { view.render_view('fm/%s' % template) }
        end

        def create

          jsonify do

            dir, name, type = path_related_params 'dir', 'name', 'type'
            path = File.join(setup.root, dir, name)
            http_path = [dir, name].join '/'

            if type == 'folder'
              FileUtils.mkdir path
              query_string = {dir: http_path}
            else
              FileUtils.touch path
              query_string = {dir: dir, file: http_path}
            end
            query_string
          end
        end

        def rename

          jsonify do

            dir, path, name = path_related_params 'dir', 'path', 'name'

            old_path = File.join(setup.root, path)
            path = File.dirname(path)
            new_path = File.join(setup.root, path, name)
            http_path = [path, name].join '/'

            raise '"%s" already exists' % name if File.file?(new_path) || File.directory?(new_path)
            FileUtils.mv old_path, new_path
            File.file?(new_path) ? {dir: dir, file: http_path} : {dir: http_path}
          end
        end

        def delete
          jsonify do
            dir, path = path_related_params 'dir', 'path'
            FileUtils.remove_entry_secure File.join(setup.root, path)
            {dir: File.directory?(File.join setup.root, dir) ? dir : File.dirname(path)}
          end
        end

        def move
          jsonify do
            dir, src, dst = path_related_params 'dir', 'src', 'dst'
            ::FileUtils.mv(::File.join(setup.root, src), ::File.join(setup.root, dst))
            current_path = ::File.join(setup.root, dir)
            {dir: File.file?(current_path) || ::File.directory?(current_path) ? dir : dst}
          end
        end

        def resize
          jsonify do
            dir, path, name = path_related_params 'dir', 'path', 'name'
            @helper.resize *[
                http.params.values_at('width', 'height').map { |v| v.to_i },
                File.join(setup.root, path),
                File.join(setup.root, File.dirname(path), name),
            ].flatten
            {dir: dir, file: [::File.dirname(path), name].join('/')}
          end
        end

        def upload

          path, name = path_related_params 'path', 'name'
          return unless path && name

          begin
            FileUtils.mv(http.params['file'][:tempfile], ::File.join(setup.root, path, name))
          rescue => e
            @errors = e
            return view.render_view('error')
          end
          1
        end

        def download
          http.attachment File.join(setup.root, path_related_params('file'))
        end

        def save
          jsonify do
            file = path_related_params 'file'
            ::File.open(::File.join(setup.root, file), 'w:utf-8') do |f|
              f << Saint::Utils.normalize_string(http.post_params['content'])
            end
            1
          end
        end

        def copy

          jsonify do
            dir, path, name = path_related_params 'dir', 'path', 'name'

            rel_path = File.join File.dirname(path), name
            full_path = File.join setup.root, rel_path
            conflicting_file = File.file?(full_path) ? rel_path : nil

            if File.directory?(full_path) && File.file?(File.join(full_path, File.basename(path)))
              conflicting_file = File.join rel_path, File.basename(path)
            end
            raise '"%s" file already exists' % conflicting_file if conflicting_file

            FileUtils.cp File.join(setup.root, path), full_path

            {dir: dir, file: rel_path}
          end
        end

        def search
          files = []
          Find.find(setup.root).select { |p| ::File.file?(p) }.each do |p|
            if ::File.basename(p) =~ /#{Regexp.escape http.params['query']}/
              files << @helper.file(p).merge(path: p.sub(setup.root, ''))
            end
          end
          view.render_view 'fm/search', files: files
        end

        def read_file
          file = path_related_params 'file'
          return unless file
          file = decode_path file
          return unless ::File.file?(full_path = ::File.join(setup.root, file))
          content, @errors = nil
          if @helper.size(full_path) > setup.edit_max_size
            @errors = 'Sorry, files bigger than %s are not editable.' % number_to_human_size(setup.edit_max_size)
          else
            begin
              content = Saint::Utils.normalize_string ::File.open(full_path, 'r:utf-8').read
            rescue => e
              @errors = 'Unable to read file: %s' % e.message
            end
          end
          response = {status: 1, content: content}
          response = {status: 0, message: view.render_view('error')} if @errors
          response.to_json
        end

        private

        def active_dir?
          default_dir = ''
          return default_dir unless dir = path_related_params('dir')
          ::File.directory?(::File.join(setup.root, dir)) ? dir : default_dir
        end

        def active_file?

          return if http.action == :upload
          return unless file = path_related_params('file')
          return unless ::File.file?(full_path = ::File.join(setup.root, file))

          node = @helper.file(full_path).update(
              path: file,
              name: ::File.basename(file),
              size: @helper.size(full_path),
              uniq: 'saint-fm-file-' << Digest::MD5.hexdigest(full_path),
              :file? => true
          )
          if node[:viewable?]
            node[:url] = setup.file_server[file]
            node[:geometry] = @helper.geometry(full_path)
          end
          node
        end

        def scan dir = nil

          @dirs ||= []
          @current_path ||= []
          dir_path = File.join(*@current_path, dir||'')
          dir_full_path = File.join(setup.root, dir_path, '')
          return unless File.directory?(dir_full_path)
          @current_path << dir if dir
          @root_folder = dir ? false : '/'

          nodes = {dirs: [], files: []}
          ls(dir_full_path).each do |n|

            name = File.basename(n)

            node = {}
            node[:dir] = dir_path
            node[:name] = name
            node[:path] = File.join([dir_path, name].select { |c| c.size > 0 })
            node[:uniq] = 'saint-fm-%s-' << Digest::MD5.hexdigest(node[:path])

            if File.directory?(n)

              node[:dir?] = true
              node[:icon] = @helper.icon('folder')
              node[:uniq] = node[:uniq] % 'dir'

              if @active_dir =~ /^#{Regexp.escape node[:path]}\//
                node[:selected_dir?] = true
              end
              if @active_dir == node[:path]
                node[:active_dir?] = true
              end

              nodes[:dirs] << node

            else

              node.update(@helper.file(n))
              node[:file?] = true
              node[:uniq] = node[:uniq] % 'file'
              node[:size] = @helper.size(n, true)

              nodes[:files] << node
            end
          end
          @dirs << {name: dir, path: dir_path, nodes: nodes}
        end

        def jsonify &proc
          begin
            response = proc.call
            if response.is_a?(Fixnum)
              response = {status: response}
            elsif response.is_a?(String)
              response = {status: 1, location: response}
            elsif response.is_a?(Hash)
              response = {status: 1, location: http.route(@query_string.merge(response))}
            end
          rescue => e
            @errors = e
            response = {status: 0, message: view.render_view('error')}
          end
          response.to_json
        end

        def path_related_params *params
          params_given = http.params.values_at(*params).compact
          return unless params_given.size == params.size
          params = params_given.map { |p| normalize_path(p).sub(/^\.\//, '') }
          params.size == 1 ? params.first : params
        end

        def encode_path path
          path.force_encoding('UTF-8')
        end

        def decode_path path
          path.force_encoding('UTF-8')
        end

        def ls path
          Dir.glob('%s/*' % path, File::FNM_DOTMATCH).
              partition { |d| test(?d, d) }.flatten.
              select { |e| File.directory?(e) || File.file?(e) }.
              reject { |e| ['.', '..'].include? File.basename(e) }
        end

      end
    end
  end
end
