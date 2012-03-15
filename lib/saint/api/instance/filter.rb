module Saint
  class InstanceApi

    def filter_instances *types
      @controller.saint.filter_instances @controller_instance.http.params, *types
    end

    def filters?
      @controller.saint.filters? @controller_instance.http.params
    end

    def filter? column
      @controller.saint.filter? column, @controller_instance.http.params
    end

  end
end
