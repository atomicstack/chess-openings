package bands

import (
	"reflect"
	"testing"
)

func TestAll_CoversFourBands(t *testing.T) {
	if len(All()) != 4 {
		t.Fatalf("want 4 bands, got %d", len(All()))
	}
}

func TestBeginner_HasNoMaia_UsesLowestLichessBucket(t *testing.T) {
	if len(MaiaNets(Beginner)) != 0 {
		t.Errorf("beginner must have no maia net")
	}
	if got := LichessBucket(Beginner); len(got) == 0 || got[0] > 1000 {
		t.Errorf("beginner should use lowest lichess bucket, got %v", got)
	}
}

func TestIntermediate_BucketsAndNets(t *testing.T) {
	buckets := LichessBucket(Intermediate)
	expectedBuckets := []int{1000, 1200}
	if !reflect.DeepEqual(buckets, expectedBuckets) {
		t.Errorf("want intermediate buckets %v, got %v", expectedBuckets, buckets)
	}

	nets := MaiaNets(Intermediate)
	expectedNets := []string{"maia-1100", "maia-1300"}
	if !reflect.DeepEqual(nets, expectedNets) {
		t.Errorf("want intermediate nets %v, got %v", expectedNets, nets)
	}
}

func TestAdvanced_BucketsAndNets(t *testing.T) {
	buckets := LichessBucket(Advanced)
	expectedBuckets := []int{1400, 1600}
	if !reflect.DeepEqual(buckets, expectedBuckets) {
		t.Errorf("want advanced buckets %v, got %v", expectedBuckets, buckets)
	}

	nets := MaiaNets(Advanced)
	expectedNets := []string{"maia-1500", "maia-1700"}
	if !reflect.DeepEqual(nets, expectedNets) {
		t.Errorf("want advanced nets %v, got %v", expectedNets, nets)
	}
}

func TestExpert_UsesMaia1900(t *testing.T) {
	nets := MaiaNets(Expert)
	found := false
	for _, n := range nets {
		if n == "maia-1900" {
			found = true
		}
	}
	if !found {
		t.Errorf("expert should include maia-1900, got %v", nets)
	}

	buckets := LichessBucket(Expert)
	hasTop := false
	for _, b := range buckets {
		if b == 2500 {
			hasTop = true
			break
		}
	}
	if !hasTop {
		t.Errorf("expert should include top bucket 2500, got %v", buckets)
	}
}
