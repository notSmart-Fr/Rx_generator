defmodule RxGenerator.Formulary.Ingestion.ControlledDrugs do
  @moduledoc """
  Reference list and pattern matching for controlled substances scheduled under the
  Bangladesh Narcotics Control Act 2018 (মাদকদ্রব্য নিয়ন্ত্রণ আইন, ২০১৮).

  Covers:
  - Opioids & Opioid Derivatives (Morphine, Fentanyl, Codeine, Pethidine, Tramadol, Tapentadol, etc.)
  - Benzodiazepines & Related Hypnotics (Diazepam, Clonazepam, Alprazolam, Midazolam, etc.)
  - Barbiturates & Non-benzodiazepine Sedatives (Phenobarbital, Zolpidem, Zopiclone, etc.)
  - Controlled Stimulants & Dissociatives (Methylphenidate, Ketamine, etc.)
  """

  @controlled_molecules [
    # Opioids & Derivatives
    "morphine",
    "codeine",
    "fentanyl",
    "pethidine",
    "meperidine",
    "tramadol",
    "tapentadol",
    "buprenorphine",
    "methadone",
    "oxycodone",
    "hydrocodone",
    "dextropropoxyphene",
    "propoxyphene",
    "pentazocine",
    "nalbuphine",
    "remifentanil",
    "sufentanil",
    "alfentanil",

    # Benzodiazepines
    "diazepam",
    "clonazepam",
    "alprazolam",
    "midazolam",
    "lorazepam",
    "bromazepam",
    "clobazam",
    "nitrazepam",
    "flurazepam",
    "oxazepam",
    "chlordiazepoxide",
    "temazepam",
    "triazolam",

    # Barbiturates & Sedatives
    "phenobarbital",
    "pentobarbital",
    "secobarbital",
    "amobarbital",
    "thiopental",
    "zolpidem",
    "zopiclone",
    "eszopiclone",

    # Stimulants & Dissociatives
    "methylphenidate",
    "ketamine",
    "amphetamine",
    "methamphetamine",
    "modafinil",
    "armodafinil"
  ]

  # Precompile regex matching whole words or boundaries for any scheduled molecule
  @molecule_pattern Regex.compile!("\\b(" <> Enum.join(@controlled_molecules, "|") <> ")\\b", "i")

  @doc """
  Returns whether a given generic name or text contains a scheduled controlled substance
  under the Bangladesh Narcotics Control Act 2018.

  ## Examples

      iex> ControlledDrugs.controlled?("Tramadol Hydrochloride")
      true

      iex> ControlledDrugs.controlled?("Paracetamol + Caffeine")
      false
  """
  @spec controlled?(String.t() | nil) :: boolean()
  def controlled?(nil), do: false
  def controlled?(""), do: false

  def controlled?(generic_name) when is_binary(generic_name) do
    Regex.run(@molecule_pattern, generic_name) != nil
  end

  @doc """
  Returns the list of all scheduled controlled molecule names (downcased).
  """
  @spec list_scheduled_molecules() :: [String.t()]
  def list_scheduled_molecules, do: @controlled_molecules
end
