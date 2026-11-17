defmodule RxGeneratorWeb.PrescriptionLive do
  use RxGeneratorWeb, :live_view

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.ShorthandParser
  alias RxGenerator.Prescriptions.SmartDefaults

  @impl true
  def mount(_params, _session, socket) do
    draft =
      case Prescriptions.get_or_create_active_draft() do
        {:ok, rx} -> rx
        _ -> nil
      end

    prescriber =
      case Prescriptions.get_active_prescriber() do
        {:ok, p} -> p
        _ -> nil
      end

    chambers =
      if prescriber do
        case Prescriptions.list_chambers_for_prescriber(prescriber.id) do
          {:ok, list} -> list
          _ -> []
        end
      else
        []
      end

    active_chamber =
      cond do
        draft && draft.chamber_config_id ->
          Enum.find(chambers, &(&1.id == draft.chamber_config_id)) ||
            List.first(chambers)

        true ->
          Enum.find(chambers, & &1.is_default) || List.first(chambers)
      end

    items = if draft, do: draft.items || [], else: []
    qr_svg = compute_qr_svg(draft)

    {:ok,
     assign(socket,
       page_title: "New Prescription",
       query: "",
       error: nil,
       candidates: [],
       highlighted_index: 0,
       draft: draft,
       prescriber: prescriber,
       chambers: chambers,
       active_chamber: active_chamber,
       items: items,
       qr_svg: qr_svg
     )}
  end

  @impl true
  def render(assigns) do
    locked = assigns.draft && assigns.draft.state == :locked

    assigns =
      assigns
      |> assign(:locked, !!locked)
      |> assign(:items_count, length(assigns.items))

    ~H"""
    <Layouts.app flash={@flash} wide>
      <div
        id="workspace-toolbar"
        class="mb-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-3 border-b border-neutral-200 pb-3 print:hidden"
      >
        <div class="flex flex-wrap items-baseline gap-3">
          <h1 class="text-lg font-semibold tracking-tight text-neutral-950">New prescription</h1>
          <span class="font-mono text-xs text-neutral-500">
            {@draft && (@draft.rx_number || "Draft")}
          </span>
          <span
            :if={@locked}
            id="prescription-locked-badge"
            class="inline-flex items-center gap-1 rounded-[2px] border border-emerald-300 bg-emerald-50 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-emerald-800"
          >
            <.icon name="hero-lock-closed" class="size-3" /> FINALIZED &amp; IMMUTABLE
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <div :if={!@locked} id="chamber-switcher" class="flex items-center gap-1.5">
            <%= if @chambers == [] do %>
              <span class="text-[11px] text-neutral-500">No chamber configured</span>
            <% else %>
              <label for="chamber-select-dropdown" class="text-[11px] text-neutral-500">
                Chamber
              </label>
              <select
                id="chamber-select-dropdown"
                name="chamber_id"
                phx-change="switch_chamber"
                class="min-h-9 rounded-[3px] border border-neutral-300 bg-white px-2 text-sm text-neutral-900 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
              >
                <option
                  :for={chamber <- @chambers}
                  value={chamber.id}
                  selected={@active_chamber && chamber.id == @active_chamber.id}
                >
                  {chamber.chamber_name}
                </option>
              </select>
            <% end %>
          </div>

          <%= if @locked do %>
            <button
              id="print-prescription-btn"
              type="button"
              phx-click="trigger_print"
              phx-disable-with="Preparing…"
              class="min-h-9 inline-flex items-center gap-2 rounded-[3px] bg-[#0F4C5C] px-4 text-sm font-semibold text-white hover:bg-[#0B3A46] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#0F4C5C]"
            >
              <.icon name="hero-printer" class="size-4" /> Print prescription
            </button>
          <% else %>
            <button
              id="finalize-prescription-btn"
              type="button"
              phx-click="finalize_prescription"
              phx-disable-with="Finalizing…"
              disabled={@items_count == 0}
              class={[
                "min-h-9 inline-flex items-center gap-2 rounded-[3px] px-4 text-sm font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#0F4C5C]",
                if(@items_count == 0,
                  do: "cursor-not-allowed bg-neutral-200 text-neutral-500",
                  else: "bg-[#0F4C5C] text-white hover:bg-[#0B3A46]"
                )
              ]}
            >
              <.icon name="hero-lock-closed" class="size-4" /> Finalize prescription
            </button>
          <% end %>
        </div>
      </div>

      <p :if={!@locked} class="mb-4 text-[11px] leading-snug text-neutral-500 print:hidden">
        Finalizing locks this sheet permanently. Print the paper on the right — it is the
        prescription.
      </p>

      <div id="workspace-grid" class="grid grid-cols-1 gap-6 lg:grid-cols-12 lg:items-start">
        <div class="space-y-4 lg:col-span-5 print:hidden">
          <.omnibar
            :if={!@locked}
            id="prescription-omnibar"
            query={@query}
            error={@error}
            candidates={@candidates}
            highlighted_index={@highlighted_index}
          />

          <.prescription_editor
            id="prescription-canvas"
            items={@items}
            clinical_warnings={SmartDefaults.detect_warnings(@items)}
            state={if(@draft, do: @draft.state, else: :draft)}
            draft={@draft}
          />
        </div>

        <div class="lg:col-span-7">
          <div class="mb-2 flex items-center justify-between print:hidden">
            <p class="text-[11px] font-medium text-neutral-500">Printed sheet</p>
            <p class="text-[11px] text-neutral-400">A4 · 210 × 297 mm</p>
          </div>

          <.a4_paper_preview
            id="a4-paper-preview"
            items={@items}
            state={if(@draft, do: @draft.state, else: :draft)}
            rx_number={if(@draft, do: @draft.rx_number, else: nil)}
            prescriber={@prescriber}
            active_chamber={@active_chamber}
            draft={@draft}
            qr_svg={@qr_svg}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("switch_chamber", %{"chamber_id" => chamber_id}, socket) do
    draft = socket.assigns.draft

    if draft && draft.state == :locked do
      {:noreply, socket}
    else
      chambers = socket.assigns.chambers

      case Enum.find(chambers, &(&1.id == chamber_id)) do
        nil ->
          {:noreply, socket}

        new_chamber ->
          updated_draft =
            if draft do
              case Prescriptions.set_prescription_chamber(draft, chamber_id) do
                {:ok, updated} -> updated
                _ -> draft
              end
            else
              draft
            end

          {:noreply, assign(socket, active_chamber: new_chamber, draft: updated_draft)}
      end
    end
  end

  @impl true
  def handle_event("update_patient_vault", params, socket) do
    draft =
      case socket.assigns.draft do
        nil ->
          case Prescriptions.get_or_create_active_draft() do
            {:ok, d} -> d
            _ -> nil
          end

        d ->
          d
      end

    if draft && draft.state == :locked do
      {:noreply, socket}
    else
      {existing_notes, existing_advice} =
        SmartDefaults.split_clinical_notes_and_advice(draft && draft.clinical_notes)

      new_notes = Map.get(params, "clinical_notes", existing_notes)
      new_advice = Map.get(params, "general_advice", existing_advice)
      combined_notes = SmartDefaults.combine_clinical_notes_and_advice(new_notes, new_advice)

      patient_params = %{
        patient_name: Map.get(params, "patient_name", draft && draft.patient_name),
        patient_phone: Map.get(params, "patient_phone", draft && draft.patient_phone),
        patient_age: Map.get(params, "patient_age", draft && draft.patient_age),
        clinical_notes: combined_notes
      }

      if draft do
        case Prescriptions.update_patient_details(draft, patient_params) do
          {:ok, updated} ->
            {:noreply, assign(socket, draft: updated)}

          {:error, _err} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("append_clinical_prefix", %{"prefix" => prefix}, socket) do
    draft = socket.assigns.draft

    if is_nil(draft) or draft.state == :locked do
      {:noreply, socket}
    else
      {notes, advice} = SmartDefaults.split_clinical_notes_and_advice(draft.clinical_notes)
      updated_notes = SmartDefaults.append_prefix(notes, prefix)
      combined = SmartDefaults.combine_clinical_notes_and_advice(updated_notes, advice)

      case Prescriptions.update_patient_details(draft, %{clinical_notes: combined}) do
        {:ok, updated} -> {:noreply, assign(socket, draft: updated)}
        {:error, _} -> {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("toggle_advice_chip", %{"advice" => chip}, socket) do
    draft = socket.assigns.draft

    if is_nil(draft) or draft.state == :locked do
      {:noreply, socket}
    else
      {notes, advice} = SmartDefaults.split_clinical_notes_and_advice(draft.clinical_notes)
      updated_advice = SmartDefaults.toggle_advice_line(advice, chip)
      combined = SmartDefaults.combine_clinical_notes_and_advice(notes, updated_advice)

      case Prescriptions.update_patient_details(draft, %{clinical_notes: combined}) do
        {:ok, updated} -> {:noreply, assign(socket, draft: updated)}
        {:error, _} -> {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("select_candidate", %{"index" => index_str}, socket) do
    case Integer.parse(to_string(index_str)) do
      {index, ""} ->
        case Enum.at(socket.assigns.candidates, index) do
          nil ->
            {:noreply, socket}

          drug ->
            query = String.trim(socket.assigns.query || "")
            parsed = ShorthandParser.parse(if query == "", do: drug.brand_name, else: query)

            {:noreply, updated_socket} =
              persist_and_assign_item(drug, parsed, query, socket)

            {:noreply, push_event(updated_socket, "set_omnibar_value", %{value: ""})}
        end

      _ ->
        {:noreply, socket}
    end
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
  def handle_event("autocomplete_candidate", %{"index" => index_str}, socket) do
    case Integer.parse(to_string(index_str)) do
      {index, ""} ->
        autocomplete_candidate_at(socket, index)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("autocomplete_candidate", _params, socket) do
    autocomplete_candidate_at(socket, socket.assigns.highlighted_index)
  end

  @impl true
  def handle_event("apply_sig_token", %{"token" => token}, socket) do
    trimmed_query = String.trim(socket.assigns.query || "")

    new_val =
      if trimmed_query == "" do
        ""
      else
        "#{trimmed_query} #{token} "
      end

    {:noreply,
     socket
     |> assign(query: new_val, candidates: [], highlighted_index: 0, error: nil)
     |> push_event("set_omnibar_value", %{value: new_val})}
  end

  @impl true
  def handle_event("update_item_sig", %{"item_id" => item_id} = params, socket) do
    draft = socket.assigns.draft

    if draft && draft.state == :locked do
      {:noreply, socket}
    else
      case Prescriptions.update_item_sig(item_id, params) do
        {:ok, updated_item} ->
          updated_items =
            Enum.map(socket.assigns.items, fn item ->
              if item.id == updated_item.id, do: updated_item, else: item
            end)

          {:noreply, assign(socket, items: updated_items, error: nil)}

        {:error, _err} ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("remove_prescription_item", %{"item_id" => item_id}, socket) do
    draft = socket.assigns.draft

    if draft && draft.state == :locked do
      {:noreply, socket}
    else
      case Prescriptions.remove_item(item_id) do
        :ok ->
          remaining = Enum.reject(socket.assigns.items, &(&1.id == item_id))
          {:noreply, assign(socket, items: remaining, error: nil)}

        {:error, _err} ->
          {:noreply, socket}
      end
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

  @impl true
  def handle_event("print", params, socket) do
    handle_event("trigger_print", params, socket)
  end

  @impl true
  def handle_event("trigger_print", _params, socket) do
    if socket.assigns.draft && socket.assigns.draft.state == :locked do
      _ = RxGenerator.Printing.Spooler.spool(socket.assigns.draft, copies: 1)
      {:noreply, push_event(socket, "print_prescription", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("finalize_prescription", _params, socket) do
    case socket.assigns.draft do
      nil ->
        {:noreply, put_flash(socket, :error, "No active draft prescription found")}

      draft ->
        case Prescriptions.finalize_prescription(draft) do
          {:ok, locked_rx} ->
            qr_svg = compute_qr_svg(locked_rx)

            {:noreply,
             socket
             |> assign(draft: locked_rx, qr_svg: qr_svg, error: nil)
             |> put_flash(
               :info,
               "Prescription #{locked_rx.rx_number} finalized and permanently locked."
             )}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            error_msg =
              Enum.map_join(errors, ", ", fn
                %{message: msg} -> msg
                other -> inspect(other)
              end)

            {:noreply, put_flash(socket, :error, "Failed to finalize: #{error_msg}")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to finalize prescription")}
        end
    end
  end

  defp autocomplete_candidate_at(socket, index) do
    candidates = socket.assigns.candidates

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

  defp compute_qr_svg(%{state: :locked, canonical_manifest: manifest, signature: sig})
       when is_binary(manifest) and is_binary(sig) do
    payload = RxGenerator.Prescriptions.Crypto.build_qr_payload(manifest, sig)

    case RxGenerator.Prescriptions.QRCode.generate_svg(payload) do
      {:ok, svg} -> svg
      _ -> nil
    end
  end

  defp compute_qr_svg(_), do: nil

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

    # Option A: Auto-apply Smart Clinical Defaults when no explicit dosage/duration/timing was typed
    {dosage_matrix, duration_expression, timing_code} =
      if parsed.dosage_matrix == :as_directed and parsed.duration_expression == :as_needed and
           is_nil(parsed.timing_code) do
        defaults = SmartDefaults.for_drug(drug)
        {defaults.dosage_matrix, defaults.duration_expression, defaults.timing_code}
      else
        {parsed.dosage_matrix, parsed.duration_expression, parsed.timing_code}
      end

    shorthand_map = %{
      dosage_matrix: dosage_matrix,
      duration_expression: duration_expression,
      timing_code: timing_code,
      special_instruction: parsed.special_instruction
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
