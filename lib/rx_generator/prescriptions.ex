defmodule RxGenerator.Prescriptions do
  use Ash.Domain,
    otp_app: :rx_generator

  resources do
    resource RxGenerator.Prescriptions.Prescription do
      define :create_prescription, action: :create
      define :list_prescriptions, action: :read
    end

    resource RxGenerator.Prescriptions.PrescriptionItem do
      define :create_item, action: :create
      define :list_items, action: :read
    end
  end
end

