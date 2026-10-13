defmodule RxGeneratorWeb.PrescriptionLive do
  use RxGeneratorWeb, :live_view

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Prescriptions.ShorthandParser
  alias RxGenerator.Prescriptions.PrescriptionItem

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "New Prescription",
       query: "",
       error: nil,
       candidates: [],
       highlighted_index: 0,
       items: []
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-100 py-10 px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <.omnibar
          id="prescription-omnibar"
          query={@query}
          error={@error}
          candidates={@candidates}
          highlighted_index={@highlighted_index}
        />

        <.prescription_canvas
          id="prescription-canvas"
          items={@items}
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("parse_and_suggest", %{"query" => query}, socket) do
    trimmed = String.trim(query)

    if trimmed == "" do
      {:noreply, assign(socket, query: query, candidates: [], error: nil)}
    else
      parsed = ShorthandParser.parse(trimmed)
      candidates = if parsed.drug_query != "", do: Search.run(parsed.drug_query, limit: 5), else: []
      {:noreply, assign(socket, query: query, candidates: candidates, error: nil)}
    end
  end

  @impl true
  def handle_event("commit_omnibar", %{"query" => query}, socket) do
    trimmed = String.trim(query)

    if trimmed == "" do
      {:noreply, socket}
    else
      parsed = ShorthandParser.parse(trimmed)
      candidates = Search.run(parsed.drug_query, limit: 1)

      case candidates do
        [drug | _] ->
          item = %PrescriptionItem{
            id: Ash.UUID.generate(),
            drug_catalog_item_id: drug.id,
            brand_name_snapshot: drug.brand_name,
            generic_name_snapshot: drug.generic_name,
            dosage_form_snapshot: drug.dosage_form,
            strength_snapshot: drug.strength,
            dosage_matrix: to_string(parsed.dosage_matrix),
            duration_expression: to_string(parsed.duration_expression),
            timing_instruction: parsed.timing_code && to_string(parsed.timing_code),
            canonical_bengali_text: nil,
            bengali_breakdown_text: nil,
            display_order: length(socket.assigns.items)
          }

          {:noreply,
           assign(socket,
             items: socket.assigns.items ++ [item],
             query: "",
             candidates: [],
             error: nil
           )}

        [] ->
          {:noreply,
           assign(socket,
             error: "Drug not found in DGDA catalog",
             query: query
           )}
      end
    end
  end
end

