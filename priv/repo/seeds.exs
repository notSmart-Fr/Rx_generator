# Script for populating sample DGDA drugs for development
alias RxGenerator.Formulary.DrugCatalogItem
alias RxGenerator.Repo

sample_drugs = [
  %{
    brand_name: "Napa",
    generic_name: "Paracetamol",
    strength: "500 mg",
    dosage_form: "Tablet",
    manufacturer: "Beximco Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-001-01",
    is_controlled: false
  },
  %{
    brand_name: "Napa Extra",
    generic_name: "Paracetamol + Caffeine",
    strength: "500 mg + 65 mg",
    dosage_form: "Tablet",
    manufacturer: "Beximco Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-001-02",
    is_controlled: false
  },
  %{
    brand_name: "Napa Rapid",
    generic_name: "Paracetamol",
    strength: "500 mg",
    dosage_form: "Tablet",
    manufacturer: "Beximco Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-001-03",
    is_controlled: false
  },
  %{
    brand_name: "Napa Extend",
    generic_name: "Paracetamol",
    strength: "665 mg",
    dosage_form: "Tablet",
    manufacturer: "Beximco Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-001-04",
    is_controlled: false
  },
  %{
    brand_name: "Ciprocin 500",
    generic_name: "Ciprofloxacin",
    strength: "500 mg",
    dosage_form: "Tablet",
    manufacturer: "Square Pharmaceuticals PLC",
    dgda_reg_no: "DAR-002-01",
    is_controlled: false
  },
  %{
    brand_name: "Ciprocin",
    generic_name: "Ciprofloxacin",
    strength: "250 mg",
    dosage_form: "Tablet",
    manufacturer: "Square Pharmaceuticals PLC",
    dgda_reg_no: "DAR-002-02",
    is_controlled: false
  },
  %{
    brand_name: "Tofen",
    generic_name: "Ketotifen",
    strength: "100 ml",
    dosage_form: "Syrup",
    manufacturer: "Beximco Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-003-01",
    is_controlled: false
  },
  %{
    brand_name: "Azithrocin 500",
    generic_name: "Azithromycin",
    strength: "500 mg",
    dosage_form: "Tablet",
    manufacturer: "Square Pharmaceuticals PLC",
    dgda_reg_no: "DAR-004-01",
    is_controlled: false
  },
  %{
    brand_name: "Rivotril",
    generic_name: "Clonazepam",
    strength: "0.5 mg",
    dosage_form: "Tablet",
    manufacturer: "Radiant Pharmaceuticals Ltd.",
    dgda_reg_no: "DAR-005-01",
    is_controlled: true
  },
  %{
    brand_name: "Maxpro",
    generic_name: "Esomeprazole",
    strength: "20 mg",
    dosage_form: "Capsule",
    manufacturer: "Square Pharmaceuticals PLC",
    dgda_reg_no: "DAR-006-01",
    is_controlled: false
  }
]

for drug <- sample_drugs do
  DrugCatalogItem
  |> Ash.Changeset.for_create(:create, drug)
  |> Ash.create()
end

# Verify FTS5 count
result = Ecto.Adapters.SQL.query!(Repo, "SELECT count(*) FROM drug_catalog_fts", [])
IO.puts("Seeded drugs successfully! Total in FTS5 index: #{inspect(result.rows)}")
