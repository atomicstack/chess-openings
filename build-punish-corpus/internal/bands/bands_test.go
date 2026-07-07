package bands

import "testing"

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
}
