LIBRARIES:=aaa xxx

OEMS:=OEM1 OEM2
OEM1:=repo/OEM1
OEM2:=repo/OEM2

SEMLA_DIR:=semla
OUT_DIR:=_outdir

.SECONDARY:
.SECONDEXPANSION:
.PHONY: release clean

release: $(foreach P, $(OEMS), $(foreach L, $(LIBRARIES), $(OUT_DIR)/$(P)/$(L)/encrypted.mol))

%/encrypted.mol: $$(SEMLA_DIR)/$$(word 2,$$(subst /, ,$$@))/pt  %/css
	$< $@ 

%/pt: 
	mkdir -p $(@D)
	cp -r $($(shell dirname $@ | cut -d / -f 2)) $(SEMLA_DIR)

$(OUT_DIR)%/css: resources/css
	mkdir -p $(@D)
	cp -r $< $@ 

clean: 
	rm -rf $(OUT_DIR) $(SEMLA_DIR)
