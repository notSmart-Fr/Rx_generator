/**
 * PrintPrescription Hook
 * Listens for "print_prescription" server-pushed events and invokes native window.print()
 */
const PrintPrescription = {
  mounted() {
    this.handleEvent("print_prescription", () => {
      // Small timeout to allow any DOM updates to flush before native print dialog opens
      setTimeout(() => {
        if (window.external && typeof window.external.ShowPrintUI === "function") {
          window.external.ShowPrintUI()
        } else {
          window.print()
        }
      }, 50)
    })
  }
}

export default PrintPrescription
