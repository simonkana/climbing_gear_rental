import { Controller } from "@hotwired/stimulus"

// Mobile navigation toggle (layouts/application). Progressive enhancement:
// the button is rendered hidden and only revealed here, so without
// JavaScript the navigation links are simply always visible.
// CSS shows the button only on small screens.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.buttonTarget.hidden = false
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  // Escape closes the menu and returns focus to the toggle.
  closeOnEscape() {
    if (!this.isOpen) return

    this.close()
    this.buttonTarget.focus()
  }

  get isOpen() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }
}
