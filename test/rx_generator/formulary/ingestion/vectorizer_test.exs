defmodule RxGenerator.Formulary.Ingestion.VectorizerTest do
  use RxGenerator.DataCase, async: true

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.Ingestion.Vectorizer

  describe "T024: Canonical semantic string formatting and MRL 256-D vector generation" do
    test "format_canonical/1 constructs '{brand_name} ({generic_name}) {dosage_form}'" do
      item = %DrugCatalogItem{
        brand_name: "Napa Extra",
        generic_name: "Paracetamol + Caffeine",
        dosage_form: "Tablet",
        strength: "500 mg + 65 mg"
      }

      assert Vectorizer.format_canonical(item) == "Napa Extra (Paracetamol + Caffeine) Tablet"
    end

    test "format_canonical/1 works with plain maps" do
      item = %{
        brand_name: "Tofen",
        generic_name: "Ketotifen",
        dosage_form: "Syrup"
      }

      assert Vectorizer.format_canonical(item) == "Tofen (Ketotifen) Syrup"
    end

    test "vectorize_text/2 returns 1024-byte float32 little-endian binary normalized to unit length" do
      text = "Napa (Paracetamol) Tablet"
      {:ok, vector_blob} = Vectorizer.vectorize_text(text)

      assert is_binary(vector_blob)
      assert byte_size(vector_blob) == 1024

      # Unpack 256 float32 values
      floats = for <<float::float-32-little <- vector_blob>>, do: float
      assert length(floats) == 256

      # Verify L2 norm is ~1.0
      norm_squared = Enum.reduce(floats, 0.0, fn f, acc -> acc + f * f end)
      l2_norm = :math.sqrt(norm_squared)
      assert_in_delta l2_norm, 1.0, 0.001
    end

    test "vectorize_batch/2 generates embeddings for a batch of texts" do
      texts = [
        "Napa (Paracetamol) Tablet",
        "Ciprocin (Ciprofloxacin) Tablet",
        "Maxpro (Esomeprazole) Capsule"
      ]

      {:ok, vectors} = Vectorizer.vectorize_batch(texts)
      assert length(vectors) == 3

      Enum.each(vectors, fn vec ->
        assert is_binary(vec)
        assert byte_size(vec) == 1024
      end)
    end

    test "normalize_and_pack/1 performs MRL prefix slicing and L2 normalization on 768-D and 1024-D Nx tensors" do
      # Simulate a 768-D embedding tensor (typical transformer output)
      raw_768 = Nx.iota({768}, type: :f32)
      packed_768 = Vectorizer.normalize_and_pack(raw_768)

      assert is_binary(packed_768)
      assert byte_size(packed_768) == 1024

      floats_768 = for <<f::float-32-little <- packed_768>>, do: f
      assert length(floats_768) == 256

      # Verify L2 norm is ~1.0
      norm_768 = :math.sqrt(Enum.reduce(floats_768, 0.0, fn f, acc -> acc + f * f end))
      assert_in_delta norm_768, 1.0, 0.001

      # Simulate a 1x1024-D batched embedding tensor
      raw_1024 = Nx.broadcast(1.0, {1, 1024})
      packed_1024 = Vectorizer.normalize_and_pack(raw_1024)

      assert is_binary(packed_1024)
      assert byte_size(packed_1024) == 1024

      floats_1024 = for <<f::float-32-little <- packed_1024>>, do: f
      assert length(floats_1024) == 256
      # For a vector of 256 ones normalized, each entry should be 1/sqrt(256) = 1/16 = 0.0625
      Enum.each(floats_1024, fn val ->
        assert_in_delta val, 0.0625, 0.001
      end)
    end

    test "normalize_and_pack/1 safely handles zero vectors without division by zero" do
      zero_tensor = Nx.broadcast(0.0, {768})
      packed = Vectorizer.normalize_and_pack(zero_tensor)

      assert is_binary(packed)
      assert byte_size(packed) == 1024

      floats = for <<f::float-32-little <- packed>>, do: f
      assert length(floats) == 256
      Enum.each(floats, fn f -> assert f == 0.0 end)
    end
  end
end
