module Saint
  class ClassApi

    # turn controller into an File Manager
    def file_manager opts = {}, &proc
      @file_manager = FmExtender.new(@controller, opts, &proc) if proc && configurable?
      @file_manager
    end

    alias :fm :file_manager
  end
end
