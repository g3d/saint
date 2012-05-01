module Saint
  class InstanceApi

    def column_instances
      unless @column_instances__controller_instance_injected
        @controller.saint.column_instances.each_value { |i| i.controller_instance @controller_instance }
        @column_instances__controller_instance_injected = true
      end
      @controller.saint.column_instances
    end
  end
end
