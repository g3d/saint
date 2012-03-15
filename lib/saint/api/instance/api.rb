module Saint
  class InstanceApi

    attr_reader :orm

    def initialize controller_instance

      @controller, @controller_instance = controller_instance.class, controller_instance

      @orm = Saint::ORM.new @controller.saint.model, @controller_instance
      @controller.saint.before.each_pair { |a, p| @orm.before a, &p }
      @controller.saint.after.each_pair { |a, p| @orm.after a, &p }

    end

    def meta_title
      @__meta_title__
    end

    def assets
      @controller.saint.render_assets
    end

    def menu
      @controller.saint.render_menu
    end

    def dashboard str = nil
      @controller.saint.render_dashboard @controller_instance, str
    end

    def ordered
      @ordered ||= Saint::ClassApi::Ordered.new @controller_instance.http.params
    end

    def method_missing *args
      @controller.saint.send *args
    end

  end
end
