package bands

type Band string

const (
	Beginner     Band = "beginner"
	Intermediate Band = "intermediate"
	Advanced     Band = "advanced"
	Expert       Band = "expert"
)

func All() []Band { return []Band{Beginner, Intermediate, Advanced, Expert} }

// LichessBucket returns the explorer "ratings" group lower-bounds to query for
// this band. The lichess explorer accepts these fixed buckets:
// 0,1000,1200,1400,1600,1800,2000,2200,2500.
// Each band's buckets are disjoint (non-overlapping).
func LichessBucket(b Band) []int {
	switch b {
	case Beginner:
		return []int{0}
	case Intermediate:
		return []int{1000, 1200}
	case Advanced:
		return []int{1400, 1600}
	case Expert:
		return []int{1800, 2000, 2200, 2500}
	}
	return nil
}

// MaiaNets returns the maia network name(s) for this band (nil for beginner).
func MaiaNets(b Band) []string {
	switch b {
	case Intermediate:
		return []string{"maia-1100", "maia-1300"}
	case Advanced:
		return []string{"maia-1500", "maia-1700"}
	case Expert:
		return []string{"maia-1900"}
	}
	return nil
}
