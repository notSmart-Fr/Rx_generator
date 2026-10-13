const Omnibar = {
  mounted() {
    this.handleEvent("set_omnibar_value", ({value}) => {
      this.el.value = value
      this.el.focus()
    })

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
        this.pushEvent("recall_last_item", {})
      }
    })
  }
}

export default Omnibar

