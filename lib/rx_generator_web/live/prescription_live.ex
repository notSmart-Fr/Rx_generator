defmodule RxGeneratorWeb.PrescriptionLive do
  use RxGeneratorWeb, :live_view

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.ShorthandParser

  @impl true
  def mount(_params, _session, socket) do
    draft =
      case Prescriptions.get_or_create_active_draft() do
        {:ok, rx} -> rx
        _ -> nil
      end

    items = if draft, do: draft.items || [], else: []

    {:ok,
     assign(socket,
       page_title: "New Prescription",
       query: "",
       error: nil,
       candidates: [],
       highlighted_index: 0,
       draft: draft,
       items: items
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
  def handle_event("parse_and_suggest", params, socket) do
    query = params["query"] || params["value"] || ""
    trimmed = String.trim(query)

    if trimmed == "" do
      {:noreply, assign(socket, query: query, candidates: [], highlighted_index: 0, error: nil)}
    else
      parsed = ShorthandParser.parse(trimmed)

      candidates =
        if parsed && parsed.drug_query != "",
          do: Search.run(parsed.drug_query, limit: 5),
          else: []

      {:noreply,
       assign(socket, query: query, candidates: candidates, highlighted_index: 0, error: nil)}
    end
  end

  @impl true
  def handle_event("navigate_suggestions", %{"direction" => direction}, socket) do
    count = length(socket.assigns.candidates)

    if count == 0 do
      {:noreply, socket}
    else
      new_index = calculate_new_index(direction, socket.assigns.highlighted_index, count)
      {:noreply, assign(socket, highlighted_index: new_index)}
    end
  end

  @impl true
  def handle_event("recall_last_item", _params, socket) do
    case socket.assigns.items do
      [] -> {:noreply, socket}
      items -> do_recall_last_item(items, socket)
    end
  end

  @impl true
  def handle_event("dismiss_suggestions", _params, socket) do
    {:noreply, assign(socket, candidates: [], highlighted_index: 0)}
  end

  @impl true
  def handle_event("autocomplete_candidate", _params, socket) do
    candidates = socket.assigns.candidates
    index = socket.assigns.highlighted_index

    case Enum.at(candidates, index) do
      nil ->
        {:noreply, socket}

      candidate ->
        # Autocomplete candidate brand name and strength into the omnibar
        new_val = "#{candidate.brand_name} "

        {:noreply,
         socket
         |> assign(query: new_val, candidates: [], highlighted_index: 0)
         |> push_event("set_omnibar_value", %{value: new_val})}
    end
  end

  @impl true
  def handle_event("commit_omnibar", %{"query" => query}, socket) do
    trimmed = String.trim(query)

    if trimmed == "" do
      {:noreply, socket}
    else
      commit_parsed_query(trimmed, query, socket)
    end
  end

  defp calculate_new_index("down", current, count), do: rem(current + 1, count)
  defp calculate_new_index("up", 0, count), do: count - 1
  defp calculate_new_index("up", current, _count), do: current - 1

  defp do_recall_last_item(items, socket) do
    last_item = List.last(items)
    remaining = Enum.slice(items, 0..-2//1)

    if last_item.id do
      Prescriptions.remove_item(last_item.id)
    end

    recalled_text = reconstruct_shorthand(last_item)

    {:noreply,
     socket
     |> assign(items: remaining, query: recalled_text, error: nil)
     |> push_event("set_omnibar_value", %{value: recalled_text})}
  end

  defp reconstruct_shorthand(item) do
    [
      item.brand_name_snapshot,
      item.dosage_matrix != "as_directed" && item.dosage_matrix,
      item.duration_expression != "as_needed" && item.duration_expression,
      item.timing_instruction
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp commit_parsed_query(trimmed, original_query, socket) do
    parsed = ShorthandParser.parse(trimmed)

    case Search.run(parsed.drug_query, limit: 1) do
      [drug | _] ->
        persist_and_assign_item(drug, parsed, original_query, socket)

      [] ->
        {:noreply, assign(socket, error: "Drug not found in DGDA catalog", query: original_query)}
    end
  end

  defp persist_and_assign_item(drug, parsed, query, socket) do
    draft = socket.assigns.draft || elem(Prescriptions.get_or_create_active_draft(), 1)
    display_order = length(socket.assigns.items)

    shorthand_map = %{
      dosage_matrix: parsed.dosage_matrix,
      duration_expression: parsed.duration_expression,
      timing_code: parsed.timing_code
    }

    case Prescriptions.add_item_to_draft(draft, drug, shorthand_map, display_order) do
      {:ok, item} ->
        {:noreply,
         assign(socket,
           draft: draft,
           items: socket.assigns.items ++ [item],
           query: "",
           candidates: [],
           error: nil
         )}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply,
         assign(socket,
           error: "Cannot add duplicate drug or modify locked prescription",
           query: query
         )}

      {:error, _other} ->
        {:noreply,
         assign(socket,
           error: "Failed to persist prescription item",
           query: query
         )}
    end
  end
end
