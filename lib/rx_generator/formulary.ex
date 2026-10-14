defmodule RxGenerator.Formulary do
  @moduledoc """
  Domain interface for the drug catalog formulary and pharmaceutical records.
  """
  use Ash.Domain,
    otp_app: :rx_generator

  resources do
    resource RxGenerator.Formulary.DrugCatalogItem do
      define :create_drug,
        action: :create,
        args: [:brand_name, :generic_name, :strength, :dosage_form, :manufacturer]

      define :list_drugs, action: :read
      define :get_drug_by_id, action: :by_id, args: [:id]
    end
  end
end
