module Saint
  module Api

    def self.included controller

      controller.respond_to?(:http) || controller.send(:include, ::Presto::Api)

      controller.ctrl.on_init do
        controller.class_exec do
          def saint
            @__saint_api_instance__
          end
        end
        @__saint_api_instance__ = Saint::InstanceApi.new(self)
      end

      class << controller
        def saint
          @__saint_api_class__ ||= Saint::ClassApi.new(self)
        end
      end

      Saint.controllers << controller
    end
  end
end
