module ApplicationHelper
  # Main navigation link; marks the current section with aria-current.
  def nav_link_to(label, path, section:)
    link_to label, path, aria: { current: ("page" if controller_name == section) }
  end

  # ARIA attributes that mark an invalid field and point to its inline message.
  def field_error_attributes(form, attribute)
    return {} unless form.object.errors.include?(attribute)

    { aria: { invalid: true, describedby: field_error_id(form, attribute) } }
  end

  # Inline error message under a field, referenced by aria-describedby.
  def field_error_message(form, attribute)
    return unless form.object.errors.include?(attribute)

    tag.p form.object.errors.messages_for(attribute).to_sentence,
      id: field_error_id(form, attribute), class: "field-error"
  end

  private
    def field_error_id(form, attribute)
      "#{form.field_id(attribute)}_error"
    end
end
