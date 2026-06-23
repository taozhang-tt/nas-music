package opencc

import "strings"

var commonT2S = strings.NewReplacer(
	"後", "后",
	"來", "来",
	"劉", "刘",
	"若", "若",
	"英", "英",
	"專", "专",
	"輯", "辑",
	"藝", "艺",
	"術", "术",
	"樂", "乐",
	"體", "体",
	"風", "风",
	"華", "华",
	"語", "语",
	"國", "国",
	"愛", "爱",
)

func T2S(value string) string {
	return commonT2S.Replace(value)
}
