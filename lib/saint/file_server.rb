module Saint
  class FileServer

    DOCUMENT_ROOT = '/__saint-file_server__/'.freeze
    EXT = '.saint-fs'.freeze

    include Presto::Api

    http.map DOCUMENT_ROOT

    def index *args
      http.send_file File.join(Saint.root, 'static', *args).sub(/#{EXT}$/i, '')
    end

    class Assets
      def initialize
        @path = '/'
      end

      def cd path
        @path = expand_path path
      end

      def js *paths
        buffer paths.map { |path| '<script type="text/javascript" src="%s"></script>' % url(path) }.join("\n")
      end

      def css *paths
        buffer paths.map { |path| '<link rel="stylesheet" href="%s"/>' % url(path) }.join("\n")
      end

      def img *paths
        buffer paths.map { |path| '<img src="%s"/>' % url(path) }.join("\n")
      end

      def output
        (@buffer||[]).join("\n")
      end

      private
      def url path
        Saint::FileServer[expand_path(path)]
      end

      def buffer str
        (@buffer ||= []) << str
        str
      end

      def expand_path path
        ::File.expand_path(path, @path).
            sub(/^\w+\:(\/+|\\+)?/, '/') # removing drive letter
      end

    end

    class << self
      include Saint::Utils

      def [] path
        [DOCUMENT_ROOT, normalize_path(path), EXT].join
      end

      def assets &proc
        instance = Assets.new
        if proc
          instance.instance_exec(&proc)
          return instance.output
        end
        instance
      end
    end

  end
end
