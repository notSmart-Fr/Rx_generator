const Omnibar = {
  mounted() {
    this.handleEvent("set_omnibar_value", ({value}) => {
      this.el.value = value
      this.el.focus()
    })

    this.windowKeydownHandler = (e) => {
      if (e.key === "Backspace") {
        const tag = (e.target && e.target.tagName) || ""
        const isEditable =
          tag === "INPUT" || tag === "TEXTAREA" || (e.target && e.target.isContentEditable)
        if (!isEditable) {
          e.preventDefault()
        }
      }
    }
    window.addEventListener("keydown", this.windowKeydownHandler)

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") {
        e.preventDefault()
        this.pushEvent("navigate_suggestions", {direction: "down"})
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        this.pushEvent("navigate_suggestions", {direction: "up"})
      } else if (e.key === "Tab") {
        const dropdown = document.getElementById("omnibar-dropdown")
        if (dropdown) {
          e.preventDefault()
          this.pushEvent("autocomplete_candidate", {})
        }
      } else if (e.key === "Escape") {
        e.preventDefault()
        this.pushEvent("dismiss_suggestions", {})
      } else if (e.key === "Backspace" && this.el.value.trim() === "") {
        e.preventDefault()
        this.pushEvent("recall_last_item", {})
      }
    })
  },
  destroyed() {
    if (this.windowKeydownHandler) {
      window.removeEventListener("keydown", this.windowKeydownHandler)
    }
  }
}

export default Omnibar
