# To collect stats: python -m cProfile -o stats main.py d: 8000

from pstats import Stats

def write(sort_by):
    with open(sort_by + '.txt', 'w') as out:
        p = Stats('stats', stream=out)
        p.sort_stats(sort_by).print_stats()

write('tottime')
write('cumtime')
