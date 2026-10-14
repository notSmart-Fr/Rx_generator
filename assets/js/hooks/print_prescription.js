/**
 * PrintPrescription Hook
 * Listens for "print_prescription" server-pushed events and invokes native window.print()
 */
const PrintPrescription = {
  mounted() {
    this.handleEvent("print_prescription", () => {
      // Small timeout to allow any DOM updates to flush before browser print dialogue opens
      setTimeout(() => {
        window.print()
      }, 50)
    })
  }
}

export default PrintPrescription
