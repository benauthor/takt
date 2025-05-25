.PHONY: sync

sync:
	rsync -avz --exclude .git/ --exclude .github/ . we@norns.local:/home/we/dust/code/takt
